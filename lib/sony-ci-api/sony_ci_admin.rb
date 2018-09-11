require 'yaml'
require 'curb'
require 'json'
require_relative 'sony_ci_basic'

class SonyCiAdmin < SonyCiBasic
  include Enumerable

  # Upload a document to Ci. Underlying API treats large and small files
  # differently, but this should treat both alike.
  def upload(file_path, log_file)
    Uploader.new(self, file_path, log_file).upload
  end

  # Just the names of items in the workspace. This may include directories.
  def list_names
    list.map { |item| item['name'] } - ['Workspace']
    # A self reference is present even in an empty workspace.
  end

  # Full metadata for a windowed set of items.
  def list(limit = 50, offset = 0)
    Lister.new(self).list(limit, offset)
  end

  # Full metadata for a queried subset of items.
  def search(query, fields = nil, limit = 50, offset = 0)
    Lister.new(self).search(query, fields, limit, offset)
  end

  # Iterate over all items.
  def each
    Lister.new(self).each { |asset| yield asset }
  end

  # Delete items by asset ID.
  def delete(asset_id)
    Deleter.new(self).delete(asset_id)
  end

  # Get detailed metadata by asset ID.
  def detail(asset_id)
    Detailer.new(self).detail(asset_id)
  end

  # Get download links by asset ID.
  def download(asset_id)
    Detailer.new(self).download(asset_id)
  end

  # Get detailed metadata for multiple asset IDs.
  def multi_details(asset_ids, fields)
    Detailer.new(self).multi_details(asset_ids, fields)
  end

  # Get asset elements
  def elements(asset_id)
    Detailer.new(self).elements(asset_id)
  end

  # Get single element
  def element(element_id)
    Detailer.new(self).element(element_id)
  end

  # Copy assets to other workspaces.
  def copy_assets(asset_ids, workspace_ids)
    Asset.new(self).copy(asset_ids, workspace_ids)
  end

  def delete_asset(asset_id)
    Asset.new(self).delete(asset_id)
  end

  # add metadata for a specific asset.
  def add_metadata(asset_id, metadata)
    Metadata.new(self).add(asset_id, metadata)
  end

  # update metadata for a specific asset.
  def update_metadata(asset_id, name, value)
    Metadata.new(self).update(asset_id, name, value)
  end

  # delete metadata for a specific asset.
  def delete_metadata(asset_id, name)
    Metadata.new(self).delete(asset_id, name)
  end

  # create a job on an asset
  def create_job_for_asset(asset_id, jobs)
    Job.new(self).create_for_asset(asset_id, jobs)
  end

  # create a general job
  def create_job(jobs)
    Job.new(self).create(jobs)
  end

  # get job status
  def job_status(job_id)
    Job.new(self).status(job_id)
  end

  class Asset < SonyCiClient #:noddoc:
    def initialize(ci)
      @ci = ci
    end

    def copy(asset_ids, workspace_ids)
      http_post('https://api.cimediacloud.com/assets/copy',
        assetIds: asset_ids,
        targets: workspace_ids.collect {|workspace_id| { workspaceId: workspace_id } }
      )
    end

    def delete(asset_id)
      http_delete('https:'"//api.cimediacloud.com/assets/#{asset_id}")
    end
  end

  class Metadata < SonyCiClient #:nodoc:
    def initialize(ci)
      @ci = ci
    end

    def add(asset_id, metadata)
      http_post("https://api.cimediacloud.com/assets/#{asset_id}/metadata",
        metadata: metadata.collect {|name, value| { name: name, value: value }}
        )
    end

    def update(asset_id, name, value)
      http_put("https://api.cimediacloud.com/assets/#{asset_id}/metadata/#{URI.escape name}", value: value)
    end

    def delete(asset_id, name)
      http_delete("https://api.cimediacloud.com/assets/#{asset_id}/metadata/#{URI.escape name}")
    end
  end

  class Job < SonyCiClient #:nodoc:
    def initialize(ci)
      @ci = ci
    end

    def create_for_asset(asset_id, jobs)
      http_post("https://api.cimediacloud.com/assets/#{asset_id}/jobs", jobs)
    end

    def create(jobs)
      http_post("https://api.cimediacloud.com/jobs", jobs)
    end

    def status(job_id)
      http_get("https://api.cimediacloud.com/jobs/#{job_id}")
    end
  end

  class Detailer < SonyCiClient #:nodoc:
    def initialize(ci)
      @ci = ci
    end

    def detail(asset_id)
      http_get('https:'"//api.cimediacloud.com/assets/#{asset_id}")
    end

    def download(asset_id)
      http_get('https:'"//api.cimediacloud.com/assets/#{asset_id}/download")
    end

    def elements(asset_id)
      response = http_get('https:'"//api.cimediacloud.com/assets/#{asset_id}/elements")
      response['items']
    end

    def element(element_id)
      response = http_get('https:'"//api.cimediacloud.com/elements/#{element_id}")
      response
    end

    def multi_details(asset_ids, fields)
      http_post('https:''//api.cimediacloud.com/assets/details/bulk',
        assetIds: asset_ids, fields: fields
        )
    end
  end

  class Deleter < SonyCiClient #:nodoc:
    def initialize(ci)
      @ci = ci
    end

    def delete(asset_id)
      http_delete('https:'"//api.cimediacloud.com/assets/#{asset_id}")
    end
  end

  class Lister < SonyCiClient #:nodoc:
    include Enumerable

    def initialize(ci)
      @ci = ci
    end

    def list(limit, offset)
      response = http_get('https:''//api.cimediacloud.com/workspaces/'"#{@ci.workspace_id}/contents",
        limit: limit, offset: offset
        )
      response['items']
    end

    def search(query, fields, limit, offset)
      response = http_get('https:'"//api.cimediacloud.com/workspaces/#{@ci.workspace_id}/search",
        query: query, fields: fields, limit: limit, offset: offset,
        kind: :asset, orderBy: :createdOn, orderDirection: :desc
        )
      response['items']
    end

    def each
      limit = 5 # Small chunks so it's easy to spot windowing problems
      offset = 0
      loop do
        assets = list(limit, offset)
        break if assets.empty?
        assets.each { |asset| yield asset }
        offset += limit
      end
    end
  end

  class Uploader < SonyCiClient #:nodoc:
    def initialize(ci, path, log_path)
      @ci = ci
      @path = path
      @log_file = File.open(log_path, 'a')
    end

    def upload
      file = File.new(@path)
      if file.size >= 5 * 1024 * 1024
        initiate_multipart_upload(file)
        part = 0
        part = do_multipart_upload_part(file, part) while part
        complete_multipart_upload
      else
        singlepart_upload(file)
      end

      row = [Time.now, File.basename(@path), @asset_id,
             @ci.detail(@asset_id).to_s.gsub("\n", ' ')]
      @log_file.write(row.join("\t") + "\n")
      @log_file.flush

      @asset_id
    end

    private

    SINGLEPART_URI = 'https://io.cimediacloud.com/upload'
    MULTIPART_URI = 'https://io.cimediacloud.com/upload/multipart'

    def singlepart_upload(file)
      params = [
        Curl::PostField.file('filename', file.path, File.basename(file.path)),
        Curl::PostField.content('metadata', JSON.generate('workspaceId' => @ci.workspace_id))
      ]
      curl = Curl::Easy.http_post(SINGLEPART_URI, params) do |c|
        c.multipart_form_post = true
        add_headers(c)
      end
      handle_errors(curl)
      @asset_id = JSON.parse(curl.body_str)['assetId']
    end

    def initiate_multipart_upload(file)
      params = JSON.generate('name' => File.basename(file),
                             'size' => file.size,
                             'workspaceId' => @ci.workspace_id)
      curl = Curl::Easy.http_post(MULTIPART_URI, params) do |c|
        add_headers(c, 'application/json')
      end
      handle_errors(curl)
      @asset_id = JSON.parse(curl.body_str)['assetId']
    end

    CHUNK_SIZE = 10 * 1024 * 1024

    def do_multipart_upload_part(file, part)
      fragment = file.read(CHUNK_SIZE)
      return unless fragment
      curl = Curl::Easy.http_put("#{MULTIPART_URI}/#{@asset_id}/#{part + 1}", fragment) do |c|
        add_headers(c, 'application/octet-stream')
      end
      handle_errors(curl)
      part + 1
    end

    def complete_multipart_upload
      curl = Curl::Easy.http_post("#{MULTIPART_URI}/#{@asset_id}/complete") do |c|
        add_headers(c)
      end
      handle_errors(curl)
    end
  end
end
