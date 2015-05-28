# sony-ci-api

[![Gem Version](https://badge.fury.io/rb/sony-ci-api.svg)](http://badge.fury.io/rb/sony-ci-api)

Provides a [Ruby interface](http://www.rubydoc.info/gems/sony-ci-api) 
to the [Sony Ci REST API](http://developers.cimediacloud.com/). 

For the examples below you will need to provide a configuration file in CWD
that looks something like:
```
username: you@example.org
password: 'your-password'
client_id: 32-hex-digits
client_secret: 32-hex-digits
workspace_id: 32-hex-digits
```

## Command-line usage

```
$ ruby bin/sony-ci-api --list
```

## Library usage

```
$ irb -Ilib -rsony-ci-api
> ci = SonyCiAdmin.new(credentials_path: 'ci.yml')
> ci.list_names # etc.
```

## Development

- Add a `ci.yml` at the top level.
- Make your changes.
- Run tests: `rspec`
- When it works, increment the version number.
- Push changes to Github

To publish gem:
- Get rubygems token, if you haven't already: `curl -u my-user-name https://rubygems.org/api/v1/api_key.yaml >
~/.gem/credentials; chmod 0600 ~/.gem/credentials`
- Create gem: `gem build sony-ci-api.gemspec`
- Push gem: `gem push sony-ci-api-x.y.z.gem`