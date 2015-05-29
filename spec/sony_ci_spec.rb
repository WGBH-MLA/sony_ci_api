require_relative '../lib/sony-ci-api/sony_ci_admin'
require 'tmpdir'

describe 'Sony Ci API' do
  let(:credentials_path) { 'config/ci.yml' }

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
    # TODO: we're not currently catching HTTP error statuses.
    xit 'blocks some filetypes (small files)' do
      ci = safe_ci
      Dir.mktmpdir do |dir|
        log_path = "#{dir}/log.txt"
        ['js', 'html', 'rb'].each do |disallowed_ext|
          path = "#{dir}/file-name.#{disallowed_ext}"
          File.write(path, "content doesn't matter")
          expect { ci.upload(path, log_path) }.to raise_exception(/Upload failed/)
        end
        expect(File.read(log_path)).to eq('')
      end
    end

    it 'allows other filetypes (small files)' do
      ci = safe_ci
      Dir.mktmpdir do |dir|
        log_path = "#{dir}/log.txt"
        path = "#{dir}/small-file.txt"
        File.write(path, 'lorem ipsum')
        expect_upload(ci, path, log_path)
      end
    end

    it 'allows big files' do
      ci = safe_ci
      Dir.mktmpdir do |dir|
        log_path = "#{dir}/log.txt"
        path = "#{dir}/big-file.txt"
        big_file = File.open(path, 'a')
        (5 * 1024).times do |k|
          big_file.write("#{k}K" + '.' * 1024 + "\n")
        end
        big_file.flush
        expect(big_file.size).to be > (5 * 1024 * 1024)
        expect(big_file.size).to be < (6 * 1024 * 1024)
        expect_upload(ci, path, log_path)
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
      ids.each { |id| ci.delete(id) } # ci.each won't work, because you delete the data under your feet.
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
