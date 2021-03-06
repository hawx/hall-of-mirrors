#!/usr/bin/env ruby

require 'open-uri'
require 'digest/md5'
require 'nokogiri'
require 'fileutils'
require 'pathname'
require 'json'
require 'uri'
require 'clive/output'
require 'tumblr_client'
require 'seq/paged'
require 'yaml'

class Hall::Tumblr
  module Update
    Tumblr.configure do |config|
      config.consumer_key        = ENV['TUMBLR_CONSUMER_KEY']
      config.consumer_secret     = ENV['TUMBLR_CONSUMER_SECRET']

      config.oauth_token         = Config.get(:tumblr, :oauth_token)
      config.oauth_token_secret  = Config.get(:tumblr, :oauth_token_secret)
    end

    module Url
      def to_local(url)
        url.split('://').last
      end

      def to_remote(path)
        'http://' + path
      end
    end

    class Resource
      def initialize(post, url, &block)
        @post  = post
        @url   = url
        @block = block || proc do |url, path|
          open(url) {|f| File.write(path, f.read)}
        end
      end

      def path
        @post.path + (Digest::MD5.hexdigest(@url) + File.extname(@url))
      end

      def inspect
        "#<Resource #{path}>"
      end

      def write
        unless File.exist?(path)
          @block.call(@url, path)
          puts '  wrote '.grey + path.basename.to_s
        end
      rescue Exception => err
        puts "  ERROR ".red.bold + @url + "\n    " + err.to_s
      end
    end

    class Post
      def initialize(blog, hash)
        @blog = blog
        @hash = hash
      end

      def to_json
        JSON.pretty_generate(@hash)
      end

      def id
        @hash['id']
      end

      def path
        @blog.path + 'posts' + id.to_s
      end

      def type
        @hash['type']
      end

      def inspect
        "#<Post #{path}>"
      end

      def resources
        return @resources if @resources

        @resources = []

        pull_from = -> string {
          doc = Nokogiri::HTML(string)
          doc.xpath('//img/@src').map(&:value)
        }

        case type
        when 'photo'
          @resources = @hash['photos'].map {|hsh|
            alt = hsh['alt_sizes'].find {|h| h['width'] == 500 }
                                           [hsh['original_size']['url'], alt ? alt['url'] : nil]
          }.flatten.compact

        when 'link'
          @resources = pull_from[@hash['description']]

        when 'video'
          @resources = []

          if @hash['permalink_url'] =~ /(youtube|vimeo).com/
            # downloads using the id as title
            # tries 720p then 270p/360p MP4
            @resources << Resource.new(self, @hash['permalink_url']) do |url, path|
              out = File.absolute_path(path)
              `youtube-dl --no-progress -f 22/18 -o #{out} #{url}`.strip
            end

          elsif @hash['video_url'] =~ /tumblr.com/
            @resources << @hash['video_url']
          end

        when 'text'
          @resources = pull_from[@hash['body']]

        when 'quote'
          @resources = pull_from[@hash['text']] + pull_from[@hash['source']]

        when 'chat'
          @resources = pull_from[@hash['body']]

        when 'audio'
          plead = '?plead=please-dont-download-this-or-our-lawyers-wont-let-us-host-audio'
          @hash['player'] =~ /audio_file=([^&]*)/
          @resources = [URI.unescape($1) + plead]
        end

        @resources.map! {|url| url.class == Resource ? url : Resource.new(self, url) }
      end

      def write(overwrite={})
        wrote = false
        print path.to_s.blue.bold
        FileUtils.mkdir_p(path)

        if !(path + 'data.json').exist? || overwrite[:data]
          File.write(path + 'data.json', to_json)
          print "\n  wrote ".grey + 'data.json'
          wrote = true
        end

        if wrote
          print "\n\n"
        else
          print "\r  skipped ".red + path.to_s.grey + "\n"
        end

        resources.each(&:write)

        wrote
      end
    end

    class Tumblelog
      def initialize(client, data)
        @client = client
        @data   = data
      end

      def name
        @data['name']
      end

      def to_json
        JSON.pretty_generate @data
      end

      def path
        ROOT + 'tumblr' + name
      end

      def posts
        @posts ||= Seq::Paged.new do |page|
          opts = {
            limit: 20,  # max.
            offset: page * 20,
            reblog_info: true,
            notes_info: true
          }

          @client.posts(name, opts)['posts'].map {|post| Post.new(self, post)}
        end
      end

      def write(break_on_skip, overwrite={})
        wrote = false
        puts path.to_s.blue.bold
        FileUtils.mkdir_p(path)

        if !(path + 'data.json').exist? || overwrite[:data]
          File.write(path + 'data.json', to_json)
          print "\n  wrote ".grey + 'data.json'
          wrote = true
        end

        if wrote
          print "\n\n"
        else
          print "\r  skipped ".red + path.to_s.grey + "\n"
        end

        posts.each do |post|
          break unless post
          break if !post.write && break_on_skip
        end

        wrote
      end
    end
  end

  command :update do
    bool :q, :quick, 'Stop writing on first skip'

    action do
      break_on_skip = get(:quick)

      client = Tumblr::Client.new
      info   = client.info

      blogs = info['user']['blogs'].map do |data|
        Update::Tumblelog.new(client, data)
      end

      blogs.each do |blog|
        blog.write(break_on_skip)
      end
    end
  end
end
