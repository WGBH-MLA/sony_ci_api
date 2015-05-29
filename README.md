# sony-ci-api

[![Gem Version](https://badge.fury.io/rb/sony-ci-api.svg)](http://badge.fury.io/rb/sony-ci-api)

Provides a [Ruby interface](http://www.rubydoc.info/gems/sony-ci-api) 
to the [Sony Ci REST API](http://developers.cimediacloud.com/). 

For the examples below you will need to have a Sony Ci account,
and your credentials must be provided in `config/ci.yml`,
based on the sample in the same directory.

## Command-line usage

```
$ sony-ci-api # lists the available options
```

This should work in any project which includes the gem, when run from the root of
the project, with `config/ci.yml` in place on that project.

## Library usage

```
$ irb -Ilib -rsony-ci-api
> ci = SonyCiAdmin.new(credentials_path: 'config/ci.yml')
> ci.list_names # etc.
```

## Development

- Make sure `config/ci.yml` is in place.
- Make your changes.
- Run tests: `rspec`
- When it works, increment the version number.
- Push changes to Github

To publish gem:
- Create a rubygems account and get your credentials, if you haven't already: 
```
curl -u my-user-name https://rubygems.org/api/v1/api_key.yaml > ~/.gem/credentials
chmod 0600 ~/.gem/credentials
```
- Create gem: `gem build sony-ci-api.gemspec`
- Push gem: `gem push sony-ci-api-X.Y.Z.gem`
