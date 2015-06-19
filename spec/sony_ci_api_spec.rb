require_relative '../lib/sony-ci-api/sony_ci_admin'
require 'yaml'
require 'tmpdir'

describe 'Sony Ci API' do
  describe 'Real Sony Ci API', not_on_travis: true do
    let(:credentials_path) { File.expand_path('../../config/ci.yml', __FILE__) }

    describe 'validation' do
      it 'requires credentials' do
        expect { SonyCiAdmin.new }.to raise_exception('No credentials given')
      end

      it 'catches option typos' do
        expect { SonyCiAdmin.new(typo: 'should be caught') }.to raise_exception('Unrecognized options [:typo]')
      end

      it 'catches creditials specified both ways' do
        expect { SonyCiAdmin.new(credentials: {}, credentials_path: {}) }.to raise_exception('Credentials specified twice')
      end

      it 'catches missing credentials' do
        expect { SonyCiAdmin.new(credentials: {}) }.to raise_exception(
          'Expected ["client_id", "client_secret", "password", "username", "workspace_id"] in ci credentials, not []'
        )
      end

      it 'catches bad credentials' do
        bad_credentials = {
          'client_id' => 'bad',
          'client_secret' => 'bad',
          'password' => 'bad',
          'username' => 'bad',
          'workspace_id' => 'bad'
        }
        expect { SonyCiAdmin.new(credentials: bad_credentials) }.to raise_exception('OAuth failed')
      end
    end

    describe 'upload / detail / download / delete' do

      describe 'small files' do
        it 'blocks some filetypes (small files)' do
          Dir.mktmpdir do |dir|
            log_path = "#{dir}/log.txt"
            ['js', 'html', 'rb'].each do |disallowed_ext|
              path = "#{dir}/file-name.#{disallowed_ext}"
              File.write(path, "content doesn't matter")
              expect { safe_ci.upload(path, log_path) }.to raise_exception(/400 Bad Request/)
            end
            expect(File.read(log_path)).to eq('')
          end
        end

        it 'allows other filetypes (small files)' do
          Dir.mktmpdir do |dir|
            log_path = "#{dir}/log.txt"
            path = "#{dir}/small-file.txt"
            File.write(path, 'lorem ipsum')
            expect_upload(safe_ci, path, log_path)
          end
        end
      end

      describe 'big files' do
        it 'allows 6M files' do
          expect_big_upload(safe_ci, 6)
        end
        big = 20
        it "allows #{big}M files" do
          expect(big * 1024 * 1024).to be > SonyCiAdmin::Uploader::CHUNK_SIZE
          expect_big_upload(safe_ci, big)
        end
      end

    end

    describe 'enumerator' do
      it 'enumerates' do
        ci = safe_ci
        count = 6
        Dir.mktmpdir do |dir|
          log_path = "#{dir}/log.txt"
          count.times { |i|
            path = "#{dir}/small-file-#{i}.mp4"
            File.write(path, "lorem ipsum #{i}")
            ci.upload(path, log_path)
          }
        end

        ids = ci.map { |asset| asset['id'] }
        expect(ids.count).to eq(count + 1) # workspace itself is in list.
        ids.each do |id|
          begin
            ci.delete(id) # ci.each won't work, because you delete the data under your feet.
          rescue
            # TODO: Why do we get 404s?
          end
        end
        expect(ci.map { |asset| asset['id'] }.count).to eq(1) # workspace can't be deleted.
      end
    end

    def safe_ci
      workspace_id = YAML.load_file(credentials_path)['workspace_id']
      expect(workspace_id).to match(/^[0-9a-f]{32}$/)
      ci = SonyCiAdmin.new(credentials_path: credentials_path) #, verbose: true) # helps with debugging
      expect(ci.access_token).to match(/^[0-9a-f]{32}$/)
      expect(ci.list_names.count).to eq(0),
                                     "Expected test workspace #{ci.workspace_id} to be empty, instead of #{ci.list_names}"
      ci
    end

    def expect_big_upload(ci, megs)
      Dir.mktmpdir do |dir|
        log_path = "#{dir}/log.txt"
        path = "#{dir}/big-file.txt"
        big_file = File.open(path, 'a')
        one_million_dollars = '$' * 1024 * 1024
        megs.times do
          big_file.write(one_million_dollars)
        end
        big_file.flush
        expect(big_file.size).to be (megs * 1024 * 1024)
        expect_upload(ci, path, log_path)
      end
    end

    def expect_upload(ci, path, log_path)
      basename = File.basename(path)
      expect { ci.upload(path, log_path) }.not_to raise_exception

      expect(ci.list_names.count).to eq(1)

      log_content = File.read(log_path)
      expect(log_content).to match(/^[^\t]+\t#{basename}\t[0-9a-f]{32}\t\{[^\t]+\}\n$/)
      id = log_content.strip.split("\t")[2]

      detail = ci.detail(id)
      expect([detail['name'], detail['id']]).to eq([basename, id])

      before = Time.now
      ci.download(id)
      middle = Time.now
      download_url = ci.download(id)
      after = Time.now

      # make sure cache is working:
      expect(after - middle).to be < 0.01
      expect(middle - before).to be > 0.1 # Often greater than 1

      expect(download_url).to match(%r{^https://ci-buckets})
      if File.new(path).size < 1024
        curl = Curl::Easy.http_get(download_url)
        curl.perform
        expect(curl.body_str).to eq(File.read(path)) # round trip!
      end

      ci.delete(id)
      expect(ci.detail(id)['isDeleted']).to eq(true)
      expect(ci.list_names.count).to eq(0)
    end
  end
  
  describe 'Mock Sony Ci API' do
    CREDENTIALS = YAML.load_file(File.expand_path('../../config/ci.yml.sample', __FILE__))
    ACCESS_TOKEN = '32-hex-access-token'
    ASSET_ID = 'asset-id'
    OAUTH = {'Authorization' => "Bearer #{ACCESS_TOKEN}"}
    DETAILS = {'id' => ASSET_ID, 'name' => 'video.mp3'}
    LOG_RE = /^\d{4}-\d{2}-\d{2}.*\t(large|small)-file\.txt\tasset-id\t\{"id"=>"asset-id", "name"=>"video\.mp3"\}\n$/

    def stub_details
      stub_request(:get, "https://api.cimediacloud.com/assets/#{ASSET_ID}").
        with(headers: OAUTH).
        to_return(status: 200, headers: {}, body: JSON.generate(DETAILS))
    end

    before(:all) do
      # TLDR: Mock tests must run last!
      # As soon as WebMock is required, it monkey patches Net::HTTP, and making
      # a regular network request becomes much harder. To get around that, 
      # we always run these tests in order, and only load WebMock when the other
      # tests have completed.
      require 'webmock/rspec'
    end

    before(:each) do
      WebMock.disable_net_connect!

      user_password = "#{URI.encode(CREDENTIALS['username'])}:#{URI.encode(CREDENTIALS['password'])}"

      stub_request(:post, "https://#{user_password}@api.cimediacloud.com/oauth2/token").
        with(body: URI.encode_www_form(
                    'grant_type' => 'password',
                    'client_id' => CREDENTIALS['client_id'],
                    'client_secret' => CREDENTIALS['client_secret'])).
        to_return(status: 200, headers: {}, body: <<-EOF
          {
            "access_token": "#{ACCESS_TOKEN}",
            "expires_in": 3600,
            "token_type": "bearer",
            "refresh_token": "32-hex-which-we-are-not-using"
          }
          EOF
        )
    end

    it 'does OAuth' do
      ci = SonyCiAdmin.new(credentials: CREDENTIALS)
      expect(ci.access_token).to eq ACCESS_TOKEN
    end

    describe 'uploads' do
      it 'does small files' do
        ci = SonyCiAdmin.new(credentials: CREDENTIALS)    
        Dir.mktmpdir do |dir|
          log_path = "#{dir}/log.txt"
          path = "#{dir}/small-file.txt"
          File.write(path, "doesn't matter")

          stub_request(:post, "https://io.cimediacloud.com/upload").
            with(body: URI.encode_www_form(
                  'filename' => path,
                  'metadata' => "{\"workspaceId\":\"#{CREDENTIALS['workspace_id']}\"}"),
                 headers: OAUTH).
            to_return(status: 200, headers: {}, body: "{\"assetId\":\"#{ASSET_ID}\"}")

          # After upload we get details for log:
          stub_details

          ci_id = ci.upload(path, log_path)
          expect(ci_id).to eq ASSET_ID
          expect(File.read(log_path)).to match LOG_RE
        end
      end

      it 'does big files' do
        ci = SonyCiAdmin.new(credentials: CREDENTIALS)    
        Dir.mktmpdir do |dir|
          log_path = "#{dir}/log.txt"
          name = 'large-file.txt'
          path = "#{dir}/#{name}"
          size = SonyCiAdmin::Uploader::CHUNK_SIZE * 2
          File.write(path, 'X' * size)

          stub_request(:post, 'https://io.cimediacloud.com/upload/multipart').
            with(body: "{\"name\":\"#{name}\",\"size\":#{size},\"workspaceId\":\"#{CREDENTIALS['workspace_id']}\"}",
                 headers: OAUTH.merge({'Content-Type'=>'application/json'})).
            to_return(status: 201, body: "{\"assetId\": \"#{ASSET_ID}\"}", headers: {})

          (1..2).each do |i|
            stub_request(:put, "https://io.cimediacloud.com/upload/multipart/#{ASSET_ID}/#{i}").
               with(body: 'X' * SonyCiAdmin::Uploader::CHUNK_SIZE,
                    headers: OAUTH.merge({'Content-Type'=>'application/octet-stream', 'Expect'=>''})).
               to_return(status: 200, body: "", headers: {})
          end

          stub_request(:post, "https://io.cimediacloud.com/upload/multipart/asset-id/complete").
             with(headers: OAUTH).
             to_return(status: 200, body: "", headers: {})

          # After upload we get details for log:
          stub_details

          ci_id = ci.upload(path, log_path)
          expect(ci_id).to eq ASSET_ID
          expect(File.read(log_path)).to match LOG_RE
        end
      end
    end

    it 'does list' do
      ci = SonyCiAdmin.new(credentials: CREDENTIALS)
      limit = 10
      offset = 20
      list = [{"kind"=>"asset", "id"=>ASSET_ID}] # IRL there is more here.

      stub_request(:get, "https://api.cimediacloud.com/workspaces/#{CREDENTIALS['workspace_id']}/contents?limit=#{limit}&offset=#{offset}").
        with(headers: OAUTH).
        to_return(status: 200, headers: {}, body: <<-EOF
          {
            "limit": #{limit},
            "offset": #{offset},
            "count": 1,
            "items": #{JSON.generate(list)}
          }
          EOF
        )

      expect(ci.list(limit, offset)).to eq list
    end

    it 'does details' do
      ci = SonyCiAdmin.new(credentials: CREDENTIALS)

      stub_details

      expect(ci.detail(ASSET_ID)).to eq DETAILS
    end

    it 'does delete' do
      ci = SonyCiAdmin.new(credentials: CREDENTIALS)

      stub_request(:delete, "https://api.cimediacloud.com/assets/#{ASSET_ID}").
        with(headers: OAUTH).
        to_return(status: 200, headers: {}, body: 'IRL JSON response goes here.')

      expect { ci.delete(ASSET_ID) }.not_to raise_exception
    end

    it 'does download' do
      ci = SonyCiAdmin.new(credentials: CREDENTIALS)

      temp_url = 'https://s3.amazon.com/ci/temp-url.mp3'

      stub_request(:get, "https://api.cimediacloud.com/assets/#{ASSET_ID}/download").
        with(headers: OAUTH).
        to_return(status: 200, headers: {}, body: JSON.generate({ 'location' => temp_url }))

      expect(ci.download(ASSET_ID)).to eq temp_url
    end

    describe 'exceptions' do
      it 'throws exception for 400' do
        BAD_ID = 'bad-id'
        ci = SonyCiAdmin.new(credentials: CREDENTIALS)

        stub_request(:get, "https://api.cimediacloud.com/assets/#{BAD_ID}/download").
          with(headers: OAUTH).
          to_return(status: 400, headers: {})

        expect { ci.download(BAD_ID) }.to raise_error
      end
    end
  end

end
