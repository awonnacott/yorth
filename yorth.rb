#!/usr/bin/env ruby
class ForthError < Exception;			end
class ForthTypeError < ForthError;		end
class ForthArgumentError < ForthError;	end
class ForthNameError < ForthError;		end
class ForthData
	attr_reader	:kind, :value
	def initialize kind, value = nil
		@kind = kind
		@value = value
	end
	def to_s;	@value.to_s;			end
	def to_i
		raise ForthTypeError.new("cannot convert #{value.class} #{@value} to an int") unless @value.to_i.to_s == @value.to_s
		@value.to_i
	end
	def + other
		begin
			@value + other.coerce(self)
		rescue Exception
			raise ForthTypeError.new("cannot add #{@kind} #{@value} and #{other.class} #{other}") unless other.is_a? ForthData
			@value + other.value
		end
	end
	def * other
		begin
			@value * other
		rescue Exception
			raise ForthTypeError.new("cannot multiply #{@kind} #{@value} and #{other.class} #{other}") unless other.is_a? ForthData
			@value + other.value
		end
	end
end
class ForthString < ForthData
	attr_reader					:value
	def initialize(value = "")	@value = value.to_s	end
	def + other
		raise ForthTypeError.new("cannot concatenate ForthString #{@value} and #{other.class} #{other}") unless other.is_a? ForthString
		ForthString.new other.to_s + @value
	end
end
class Code
	attr_reader		:code
	def initialize code = [], scope = Hash[]
		@code = code
		@scope = scope
	end
	def to_s;		@code.to_s;					end
	def to_i;		@code.last.to_i;			end
	def inspect;	[@code, @scope].inspect;	end
	def load *args
		args.flatten!
		args.each do |arg|
			begin
				File.open(arg).each do |line|
					begin
						evaluate line.split
					rescue ForthError => error
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
			print "$ "
			evaluate gets.chomp.split
		rescue ForthError => error
			puts "#{error.class}: #{error}"
		end while true
	end
	def evaluate words
		@code = words
		until @code == []
			last = draw :nil
			puts "=> #{last.inspect}" unless last.nil?
		end
	end
	def collect stop
		stop_index = @code.rindex stop 
		raise ForthArgumentError.new("non-terminting #{stop} clause") unless stop_index
		@code.slice! stop_index
		@code.slice!(stop_index, @code.length)
	end
	def draw *args
		args = args.flatten.uniq
		word = @code.pop
		if word.to_i.to_s == word.to_s	then word.to_i
		elsif word.is_a? ForthString	then word
		elsif word.is_a? Code
			begin
				        Marshal.load(Marshal.dump(word)).draw
			rescue ForthArgumentError
				@code = @code + word.code
				        draw
			end
		elsif (@scope[word]) && (args.include? :block)
			            @scope[word]
		elsif @scope[word]
		    @code << @scope[word]
			            draw
		else			case word
		when nil		then raise ForthArgumentError.new("ran out of values") unless args.include? :nil
		when '='		then draw == draw
		when '+'		then draw + draw
		when '-'		then 0 - draw + draw
		when '*'		then draw * draw
		when '/'		then 1.0 / draw * draw
		when '"'		then ForthString.new collect('"').join(" ")
		when 'bye'		then exit
		when 'del'		then @scope.delete @code.pop
		when 'inspect'	then self
		when 'load'		then load @code.pop
		when 'pop'      then $main.draw
		when '.'
			puts draw
			            draw args
		when ".."
			item = draw :block
			            puts "#{item.class} #{item.inspect}"
		when '}'
			block = Code.new collect('{')
			            return block if args.include? :block
			@code << block
			            draw
		when ')'
			collect '('
			            draw args
#	Implement loops
		when 'set'
			name = @code.pop
			block = draw :block
			@scope[name] = block
			            return nil if args.include? :nil
			            return block if (args.include? :block) || (block.class != Code)
			            draw
		else			raise ForthNameError.new("undefined word #{word}")
		end
		end
	end
end
$main ||= Code.new
if inspect == "main"
	$main.interpret unless ARGV[0]
	debug = ["--debug", "-i", "/i"].include? ARGV[0].downcase
	ARGV.slice! 0 if debug
	$main.load ARGV
	$main.interpret if debug
end