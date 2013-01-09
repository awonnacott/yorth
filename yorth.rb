#!/usr/bin/env ruby
require 'readline'
class YorthError < Exception;			end
class YorthTypeError < YorthError;		end
class YorthArgumentError < YorthError;	end
class YorthNameError < YorthError;		end
class YorthData
	attr_reader	:value
	def initialize kind = nil, value = nil
		@kind = kind
		@value = value
	end
	def dup;	Marshal.load(Marshal.dump(self))	end
	def to_s;		@value.to_s;					end
	def to_i
		raise YorthTypeError.new("cannot convert #{value.class} #{@value} to an int") unless @value.to_i.to_s == @value.to_s
		@value.to_i
	end
	def inspect
		[@kind, @value].inspect
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
			@value * other.value
		end
	end
end
class YorthArray < YorthData
	def initialize strings = [], enclosure = Code.new
		@value = []
		while strings.include?(',')
			comma = strings.index(',')
			strings.slice! comma
			@value << Closure.new(strings.slice!(0,comma), enclosure).draw
		end
		@value << Closure.new(strings, enclosure).draw
	end
end
class YorthString
	def initialize value = "";	@value = value.to_s		end
	def dup;					YorthString.new @value	end
	def inspect;				@value.inspect			end
	def to_s;					@value					end
	def to_i
		nil unless @value.to_i.to_s == @value.to_s
		@value.to_i
	end
	def + other
		raise YorthTypeError.new("cannot concatenate YorthString #{@value} and #{other.class} #{other}") unless other.is_a? YorthString
		YorthString.new @value + other.to_s
	end
end
class Closure
	def initialize code = [], enclosure = Closure.new([],nil, nil), caller = Closure.new([], nil, nil)
		@code = code
		@enclosure = enclosure
		@scope = Hash[]
		@caller = caller
	end
	def to_s;		@code.to_s;						end
	def to_i;		nil;							end
	def inspect;	[@code, @scope].inspect;		end
	def terminates;	@code == [];					end
	def dup caller = Closure.new([], nil); Closure.new(Marshal.load(Marshal.dump(@code)), @enclosure, caller)	end
	def has? word
		return true unless @scope[word].nil?
		return false if @enclosure.nil?
		@enclosure.has? word
	end
	def resolve word
		return @scope[word].value unless @scope[word].nil?
		return nil if @enclosure.nil?
		@enclosure.resolve word
	end
	def declare word
		@scope[word] = YorthData.new
		nil
	end
	def unassign word
		if not @scope[word].nil?
			@scope[word] = nil
			nil
		elsif @enclosure.nil?
			nil
		else
			@enclosure.unassign word
		end
	end
	def assign (word, value)
		if @scope[word] != nil
			@scope[word] = YorthData.new(value.class, value)
			nil
		elsif @enclosure.nil?
			raise YorthNameError.new("'#{word}' has not been declared")
		else
			@enclosure.assign(word, value)
		end
	end
	def load *args
		args.flatten!
		args.each do |arg|
			library = arg
			$libpath.each do |dir|
				begin
					Dir.glob("#{File.expand_path(dir)}/#{arg}") do |lib|
						library = lib
					end
				rescue Errno::ENOENT
				end
			end
			begin
				File.open(library).each do |line|
					begin
						evaluate line.split
					rescue YorthError => error
						puts "#{error.class}: #{error}"
					end
				end
				puts "#{arg} loaded"
			rescue Errno::ENOENT
				puts "#{arg} does not exist"
			end
		end
		nil
	end
	def interpret
		puts "yorth interpreter initialized"
		begin
			print "<= "
			evaluate Readline.readline("", true).chomp.split
		rescue YorthError => error
			puts "#{error.class}: #{error}"
		end while true
	end
	def parse code
		i = 0
		pos_f = []
		pos_a = []
		code.each do |word|
			case word
			when '('
				stop_index = code.index(')')
				raise YorthArgumentError.new("non-terminting comment") if stop_index.nil?
				return code.take(i) + code[stop_index+1..code.length]
			when '"'
				stop_index = code[i..code.length].index('"')+i+2
				raise YorthArgumentError.new("non-terminting string") if stop_index.nil?
				return code.take(i) + [YorthString.new(code[i+1..stop_index-1].join(' '))] + code[stop_index+1..code.length]
			when "'"
				stop_index = code[i..code.length].index("'")+i+2
				raise YorthArgumentError.new("non-terminting string") if stop_index.nil?
				return code.take(i) + [YorthString.new(code[i+1..stop_index-1].join(' '))] + code[stop_index+1..code.length]
			when '{'
				pos_f << i
			when '}'
				raise YorthArgumentError.new("non-opened function") if pos_f.nil? or pos_f == []
				beginpoint = pos_f.pop
				if pos_f == []
					beginning = code.shift(beginpoint)
					code.shift(1)
					function = Closure.new(code.shift(i-beginpoint-1).reverse, self)
					function.parse!
					code.shift(1)
					return beginning + [function] + code
				end
			when '['
				pos_a << i
			when ']'
				raise YorthArgumentError.new("non-opened array") if pos_a.nil? or pos_a == []
				beginpoint = pos_a.pop
				if pos_f == []
					beginning = code.shift(beginpoint)
					code.shift(1)
					array = YorthArray.new(code.shift(i-beginpoint-1).reverse, self)
					code.shift(1)
					return beginning + [array] + code
				end
			end
			i += 1
		end
		raise YorthArgumentError.new("non-terminating function") unless pos_f == [] or pos_f.nil?
		code
	end
	def parse!
		parsed = @code.reverse
		begin
			code = parsed
			parsed = parse code
		end until parsed == code
		@code = code.reverse
	end
	def evaluate code
		@code = code.reverse
		parse!
		until @code == []
			begin
				last = draw :nil
				puts "=> #{last.inspect}" unless last.nil?
			rescue TypeError => error
				raise YorthTypeError.new("#{error} in #{code}")
			end
		end
	end
	def draw *args
		args = args.flatten.uniq
		word = @code.pop
		if word.respond_to? :to_i and word.to_i.to_s == word.to_s	then word.to_i
		elsif word.is_a? YorthString	then word
		elsif word.is_a? Closure
			return word if args.include? :block
			function = word.dup self
			until function.terminates
				result = function.draw
			end
			result
		elsif has? word
			@code << resolve(word)
			draw args
		else			case word
		when nil		then raise YorthArgumentError.new("ran out of values") unless args.include? :nil
		when '='		then draw == draw
		when '~'		then draw != draw
		when '>'		then draw > draw
		when '<'		then draw < draw
		when '+'		then draw + draw
		when '-'		then draw - draw
		when '*'		then draw * draw
		when '.'		then puts draw
		when '/'		then draw / draw
		when 'bye'		then exit
		when 'clear'	then @scope = Hash[]
		when 'del'		then unassign @code.pop
		when 'false'	then false
		when 'inspect'	then self
		when 'let'		then declare @code.pop
		when 'load'		then load @code.pop
		when 'lsp'		then name = @code.pop; declare name; assign(name, @enclosure.draw)
		when 'not'		then not draw
		when 'or'		then t1 = draw; t2 = draw; t1 or t2
		when 'pop'		then @caller.draw args
		when 'set'		then assign(@code.pop, draw(:block))
		when 'true'		then true
		when ".."
			item = draw :block
			puts "#{item.class} #{item.inspect}"
		when 'if'
			condition = draw :block
			whentrue = draw :block
			whenfalse = draw :block
			if condition.is_a? Closure
				@code << condition
				condition = draw
			end
			if condition
				if whentrue.is_a? Closure and not args.include? :block
					@code << whentrue
					draw args
				else
					whentrue
				end
			else
				if whenfalse.is_a? Closure and not args.include? :block
					@code << whenfalse
					draw args
				else
					whenfalse
				end
			end
		else raise YorthNameError.new("undefined word #{word.inspect}")
		end
		end
	end
end
$libpath = if RUBY_PLATFORM.downcase.include? "linux"	then ["./lib",	"/usr/share/yorth/lib",	"/usr/lib/yorth/**",	"~/.yorth/lib/**"]
		elsif RUBY_PLATFORM.downcase.include? "darwin"	then ["./lib",	"/usr/share/yorth/lib",	"/usr/lib/yorth/**",	"~/.yorth/lib/**"]
		elsif RUBY_PLATFORM.downcase.include? "win"		then ["./lib",	"/Program Files/yorth/lib/**",					"~/.yorth/lib/**"]
														else ["./lib",													"~/.yorth/lib/**"]
end
if inspect == "main"
	main = Closure.new
	main.load "prelude.wye"
	main.interpret unless ARGV[0]
	debug = ["--debug", "-i", "/i"].include? ARGV[0].downcase
	ARGV.slice! 0 if debug
	main.load ARGV
	main.interpret if debug
end