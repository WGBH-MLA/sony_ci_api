class SonyCiClient #:nodoc:

  def http_get(get_url, params = {})
    get_url += '?' + params.to_query if params.any?
    Rails.logger.debug "  CI GET #{get_url}"
    curl = Curl::Easy.http_get(get_url) do |c|
      add_headers(c)
    end
    handle_errors(curl)
    JSON.parse curl.body_str
  end

  def http_post(post_url, params = {})
    json_params = JSON.generate params
    Rails.logger.debug "  CI POST #{post_url}"
    Rails.logger.debug "       => #{json_params}"
    curl = Curl::Easy.http_post(post_url, json_params) do |c|
      add_headers(c, 'application/json')
    end
    handle_errors(curl)
    JSON.parse curl.body_str
  end

  def http_put(put_url, params = {})
    json_params = JSON.generate params
    Rails.logger.debug "  CI PUT #{put_url}"
    Rails.logger.debug "      => #{json_params}"
    curl = Curl::Easy.http_put(put_url, json_params) do |c|
      add_headers(c, 'application/json')
    end
    handle_errors(curl)
    JSON.parse curl.body_str
  end

  def http_delete(delete_url)
    Rails.logger.debug "  CI DELETE #{delete_url}"
    curl = Curl::Easy.http_delete(delete_url) do |c|
      add_headers(c)
    end
    handle_errors(curl)
  end

  def add_headers(curl, mime = nil)
    # on_missing and on_failure exist...
    # but any exceptions are caught and turned into warnings:
    # You need to check the response code at the end
    # if you want the execution path to change.
    curl.verbose = @ci.verbose
    curl.headers['Authorization'] = "Bearer #{@ci.access_token}"
    curl.headers['Content-Type'] = mime if mime
  end

  def handle_errors(curl)
    fail "#{curl.status}: #{curl.url}\nHEADERS: #{curl.headers}\nPOST: #{curl.post_body}\nRESPONSE: #{curl.body}" if curl.response_code.to_s !~ /^2../
  end
end
