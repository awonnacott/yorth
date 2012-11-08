#!/usr/bin/env ruby
class YorthError < Exception;			end
class YorthTypeError < YorthError;		end
class YorthArgumentError < YorthError;	end
class YorthNameError < YorthError;		end
class YorthData
	attr_reader	:kind, :value
	def initialize kind, value = nil
		@kind = kind
		@value = value
	end
	def to_s;	@value.to_s;			end
	def to_i
		raise YorthTypeError.new("cannot convert #{value.class} #{@value} to an int") unless @value.to_i.to_s == @value.to_s
		@value.to_i
	end
	def + other
		begin
			@value + other.coerce(self)
		rescue Exception
			raise YorthTypeError.new("cannot add #{@kind} #{@value} and #{other.class} #{other}") unless other.is_a? YorthData
			@value + other.value
		end
	end
	def * other
		begin
			@value * other
		rescue Exception
			raise YorthTypeError.new("cannot multiply #{@kind} #{@value} and #{other.class} #{other}") unless other.is_a? YorthData
			@value + other.value
		end
	end
end
class YorthString < YorthData
	attr_reader					:value
	def initialize(value = "")	@value = value.to_s	end
	def + other
		raise YorthTypeError.new("cannot concatenate YorthString #{@value} and #{other.class} #{other}") unless other.is_a? YorthString
		YorthString.new other.to_s + @value
	end
end
class Closure
	def initialize code = [], enclosure = Closure.new([],nil)
		@code = code
		@enclosure = enclosure
		@scope = Hash[]
	end
	def to_s;		@code.to_s;						end
	def to_i;		dup.draw.to_i;					end
	def inspect;	[@code, @scope].inspect;		end
	def dup;	Marshal.load(Marshal.dump(self))	end
	def return_class;	dup.draw.class;				end
	def has? word
		return true unless @scope[word].nil?
		return false if @enclosure.nil?
		@enclosure.has? word
	end
	def resolve word
		return @scope[word] unless @scope[word].nil?
		return nil if @enclosure.nil?
		@enclosure.resolve word
	end
	def load *args
		args.flatten!
		args.each do |arg|
			begin
				File.open(arg).each do |line|
					begin
						evaluate line.split
					rescue YorthError => error
						puts "#{error.class}: #{error}"
					end
				end
			rescue Exception
				puts "#{arg} does not exist"
			end
		end
	end
	def interpret
		puts "yorth interpreter initialized"
		begin
			print "<= "
			evaluate gets.chomp.split
		rescue YorthError => error
			puts "#{error.class}: #{error}"
		end while true
	end
	def evaluate code
		@code = code
		until @code == []
			begin
				last = draw :nil
				puts "=> #{last.inspect}" unless last.nil?
			rescue TypeError => error
				raise YorthTypeError.new("#{error} in #{code}")
			end
		end
	end
	def collect stop
		stop_index = @code.rindex stop 
		raise YorthArgumentError.new("non-terminting #{stop} clause") unless stop_index
		@code.slice! stop_index
		@code.slice!(stop_index, @code.length)
	end
	def draw *args
		args = args.flatten.uniq
		word = @code.pop
		if word.to_i.to_s == word.to_s	then word.to_i
		elsif word.is_a? YorthString	then word
		elsif word.is_a? Closure		then word.dup.draw
#			begin
#				word.dup.draw
#			rescue YorthArgumentError
#				@code = @code + word.code
#				draw
#			end
		elsif (@scope[word]) && (args.include? :block)
			@scope[word]
		elsif @scope[word]
			@code << @scope[word]
			draw
		elsif (has? word) && (args.include? :block)
			resolve word
		elsif has? word
			@code << resolve(word)
			draw
# outdated because {} turns into codeblocks now?
		else			case word
		when nil		then raise YorthArgumentError.new("ran out of values") unless args.include? :nil
		when '='		then draw == draw
		when '+'		then draw + draw
		when '-'		then 0 - draw + draw
		when '*'		then draw * draw
		when '/'		then 1.0 / draw * draw
		when '"'		then YorthString.new collect('"').join(" ")
		when 'bye'		then exit
		when 'del'		then @scope.delete @code.pop
		when 'inspect'	then self
		when 'load'		then load @code.pop
		when 'pop'      then enclosure.draw
		when '.'		then puts draw
		when ".."
			item = draw :block
			puts "#{item.class} #{item.inspect}"
		when '}'
			block = Closure.new(collect('{'),@scope.dup)
			            return block if args.include? :block
			@code << block
			            draw
		when ')'
			collect '('
			draw args
#	Implement loops
		when 'set'
			@scope[@code.pop] = draw :block
			nil
		else			raise YorthNameError.new("undefined word #{word}")
		end
		end
	end
end
if inspect == "main"
	Closure.new.interpret unless ARGV[0]
	debug = ["--debug", "-i", "/i"].include? ARGV[0].downcase
	ARGV.slice! 0 if debug
	Closure.new.load ARGV
	Closure.new.interpret if debug
end