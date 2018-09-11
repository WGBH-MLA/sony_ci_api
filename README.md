# Sony Ci API

[![Gem Version](https://badge.fury.io/rb/sony_ci_api.svg)](http://badge.fury.io/rb/sony_ci_api)
[![Build Status](https://travis-ci.org/WGBH/sony_ci_api.svg)](https://travis-ci.org/WGBH/sony_ci_api)

Provides a [Ruby interface](http://www.rubydoc.info/gems/sony_ci_api) 
to the [Sony Ci REST API](http://developers.cimediacloud.com/). Features:
- Takes care of OAuth.
- Single method handles upload of any size file.
- Use `each` or `map` to iterate over everything in a workspace, rather worrying
about batches of 50 at a time.
- HTTP 4xx responses cause exceptions.

For the examples below you will need to have a Sony Ci account,
and your credentials must be provided in `config/ci.yml`,
based on the sample in the same directory.

## Command-line usage

```
$ sony_ci_api # lists the available options
```

This should work in any project which includes the gem, when run from the root of
the project, with `config/ci.yml` in place on that project.

## Library usage

```
$ irb -Ilib -rsony_ci_api
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
- Create gem: `gem build sony_ci_api.gemspec`
- Push gem: `gem push sony_ci_api-X.Y.Z.gem`
