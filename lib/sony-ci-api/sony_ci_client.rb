class SonyCiClient #:nodoc:
  def add_headers(curl, mime=nil)
    # on_missing and on_failure exist...
    # but any exceptions are caught and turned into warnings:
    # You need to check the response code at the end
    # if you want the execution path to change.
    curl.verbose = @ci.verbose
    curl.headers['Authorization'] = "Bearer #{@ci.access_token}"
    curl.headers['Content-Type'] = mime if mime
  end
  def handle_errors(curl)
    raise "#{curl.status}: #{curl.url}" if curl.response_code.to_s !~ /^2../
  end
end