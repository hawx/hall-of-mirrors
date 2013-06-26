#!/usr/bin/env ruby

require 'nokogiri'
require 'digest/md5'
gem 'sass'; require 'sass'
require 'haml'
require 'sinatra'
require 'json'
require 'time'
require 'pathname'
require 'seq'
require 'seq/pager'
require_relative '../_common/global'

PAGE_SIZE = 10
set :views, File.dirname(__FILE__) + '/app'


def format_time(str)
  Time.parse(str).strftime('%d %B %Y')
end

class Post
  def initialize(user, id)
    @user = user
    @id = id
  end

  def name
    data['title']
  end

  def path
    @user.path + 'posts' + @id
  end

  def id
    data['id']
  end

  def data
    @data ||= JSON.parse(File.read(path + "data.json"))
  end

  def url
    @user.url + '/post/' + @id
  end

  def resource_path(url)
    "/resource/#{@user.name}/#{id}/" + (Digest::MD5.hexdigest(url) + File.extname(url))
  end

  def audio_path(url)
    plead = '?plead=please-dont-download-this-or-our-lawyers-wont-let-us-host-audio'
    resource_path(url + plead)
  end

  # Yeah, this is awful
  def image_urls
    photos.map {|h|
      o = h['original_size']['url']
      if File.exist?(resource_path(o))
        resource_path(o)
      else
        a = h['alt_sizes'].find {|h| h['width'] == 500 }
        if a
          resource_path(a['url'])
        else
          resource_path(o)
        end
      end
    }
  end

  def fix_resources(text)
    doc = Nokogiri::HTML(text)
    resources = doc.xpath('//img/@src').map(&:value)

    resources.each do |resource|
      text = text.gsub resource, resource_path(resource).to_s
    end

    text
  end

  def method_missing(sym, *args)
    if data.has_key?(sym.to_s)
      return data[sym.to_s]
    end

    if sym.to_s.end_with?('?')
      return data.has_key?(sym[0..-2].to_s) && !data[sym[0..-2].to_s].empty?
    end

    super
  end
end

class User
  def self.all
    Dir[ROOT + 'tumblr' + '*/'].reject {|path|
      path.end_with?('/app/')
    }.map {|path|
      new(path.split("/").last)
    }
  end

  def initialize(name)
    @name = name
  end

  def data
    @data ||= JSON.parse(File.read(path + "data.json"))
  end

  def name
    data['name']
  end

  def path
    ROOT + 'tumblr' + @name
  end

  def url
    '/' + @name
  end

  def find(post_id)
    posts.find {|post| post.id == post_id.to_i }
  end

  def posts
    @posts ||= Dir[path + 'posts' + '*']
      .map {|p| Post.new(self, p.split('/').last) }
      .sort_by {|p| p.data['id']}
      .reverse
  end

  def __pages
    @pages ||= Seq::Pager.new(PAGE_SIZE, posts)
  end

  def page(num)
    __pages.page = num
    __pages.curr
  end

  def pages
    __pages.pages
  end

  def range
    __pages.range(2, 2, 2)
      .reject(&:empty?)
      .map {|a| a << nil }
      .flatten.tap(&:pop)
  end
end


get '/styles.css' do
  sass :styles
end

get '/' do
  @users = User.all

  haml :index
end

get '/:user/?' do
  @user  = User.new(params[:user])
  @page  = 0
  @posts = @user.page(@page)

  haml :list
end

get '/:user/page/:num/?' do
  redirect "/#{params[:user]}" if params[:num] == "0"

  @user  = User.new(params[:user])
  @page  = params[:num].to_i
  @posts = @user.page(@page)

  haml :list
end

get '/resource/:user/:post/:resource.mp3/?' do
  path = ROOT + 'tumblr' + params[:user] + 'posts' + params[:post] + params[:resource]
  send_file path, :type => :mp3
end

get '/resource/:user/:post/:resource/?' do
  path = ROOT + 'tumblr' + params[:user] + 'posts' + params[:post] + params[:resource]
  send_file path
end

get '/:user/post/:id/?' do
  @user = User.new(params[:user])

  @post = @user.find(params[:id])
  return "No post found" unless @post

  @posts = [@post]

  haml :list
end
