class SonyCiClient #:nodoc:
  def add_headers(curl, mime=nil)
    # TODO: Is this actually working?
    # curl.on_missing { |data| puts "4xx: #{data}" }
    # curl.on_failure { |data| puts "5xx: #{data}" }
    curl.verbose = @ci.verbose
    curl.headers['Authorization'] = "Bearer #{@ci.access_token}"
    curl.headers['Content-Type'] = mime if mime
  end
end