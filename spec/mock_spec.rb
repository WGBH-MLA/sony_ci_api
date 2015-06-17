require_relative '../lib/sony-ci-api/sony_ci_admin'
require 'webmock/rspec'
require 'yaml'

describe 'Mock Sony Ci API' do
  CREDENTIALS_PATH = 'config/ci.yml.sample'
  ACCESS_TOKEN = '32-hex-access-token'
  
  before(:all) do
    
    WebMock.disable_net_connect!
    
    creds = YAML.load_file(CREDENTIALS_PATH)
    
    user_password = "#{URI.encode(creds['username'])}:#{URI.encode(creds['password'])}"
    
    stub_request(:post, "https://#{user_password}@api.cimediacloud.com/oauth2/token").
      with(body: ['grant_type=password',
                  "client_id=#{creds['client_id']}",
                  "client_secret=#{creds['client_secret']}"].join('&')).
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
    ci = SonyCiAdmin.new(credentials_path: CREDENTIALS_PATH)
    expect(ci.access_token).to eq ACCESS_TOKEN
  end
end
