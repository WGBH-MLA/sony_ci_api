require_relative '../lib/sony-ci-api/sony_ci_admin'
require 'webmock/rspec'
require 'yaml'
require 'tmpdir'

describe 'Mock Sony Ci API' do
  CREDENTIALS = YAML.load_file(File.expand_path('../../config/ci.yml.sample', __FILE__))
  ACCESS_TOKEN = '32-hex-access-token'
  ASSET_ID = 'asset-id'
  OAUTH = {'Authorization' => "Bearer #{ACCESS_TOKEN}"}
  
  before(:each) do
    # I don't really understand the root problem, but
    # before(:all) caused the second test to fail, even with .times(x)
    
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
  
  after(:all) do
    WebMock.disable!
  end
  
  it 'does OAuth' do
    ci = SonyCiAdmin.new(credentials: CREDENTIALS)
    expect(ci.access_token).to eq ACCESS_TOKEN
  end
  
  it 'does upload' do
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
      stub_request(:get, "https://api.cimediacloud.com/assets/asset-id").
         with(headers: OAUTH).
         to_return(status: 200, headers: {}, body: "{}")
      
      ci_id = ci.upload(path, log_path)
      expect(ci_id).to eq ASSET_ID
    end
  end
  
  # TODO: test large upload
  
  it 'does list' do
    ci = SonyCiAdmin.new(credentials: CREDENTIALS)
    limit = 10
    offset = 20
    list = [{"kind"=>"asset", "id"=>"asset-id"}] # IRL there is more here.
    
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
    details = {'id' => ASSET_ID, 'name' => 'video.mp3'} # IRL there is more here.
    
    stub_request(:get, "https://api.cimediacloud.com/assets/#{ASSET_ID}").
      with(headers: OAUTH).
      to_return(status: 200, headers: {}, body: JSON.generate(details))
    
    expect(ci.detail(ASSET_ID)).to eq details
  end
  
  # TODO: delete
end
