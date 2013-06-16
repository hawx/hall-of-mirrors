# @example
#
#   class TestWriter
#     include Writer
#
#     def path
#       HERE + '_'
#     end
#
#     def data
#       {
#         a: 1,
#         b: 2
#       }
#     end
#
#     writeable :test, 'test.json', :data
#   end
#
#   tw = TestWriter.new
#   tw.write
#
module Writer
  def self.included(klass)
    klass.extend(ClassMethods)
  end

  class Writeable
    attr_reader :key, :path, :data, :cond

    def initialize(key, path, data, &cond)
      @key, @path, @data, @cond = key, path, data, cond
    end
  end

  module ClassMethods
    def writeable(key, path, data, &cond)
      wr = Writeable.new(key, path, data, &cond)
      self.instance_variable_set(:@__writeables, writeables + [wr])
    end

    def writeables
      self.instance_variable_get(:@__writeables) || []
    end
  end

  def write(overwrite={})
    wrote = false

    print path.to_s.blue.bold
    FileUtils.mkdir_p path

    self.class.writeables.each do |wr|
      next if wr.cond && !wr.cond.call(self)
      next if wr.path && (path + wr.path).exist? && !overwrite[wr.key]

      if wr.data.respond_to?(:call)
        written = wr.data.call(self, wr)
      else
        data = self.send(wr.data)
        if data.is_a?(Hash)
          File.write(path + wr.path, JSON.pretty_generate(data))
        else
          File.write(path + wr.path, data)
        end
      end

      print "\n  wrote ".grey + (wr.path || written)
      wrote = true
    end

    if wrote
      print "\n\n"
    else
      print "\r  skipped ".red + path.to_s.grey + "\n"
    end

    wrote
  end
end
