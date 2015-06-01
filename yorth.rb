#!/usr/bin/ruby
require 'readline'

class YorthError < Exception;			end
class YorthTypeError < YorthError;		end
class YorthArgumentError < YorthError;	end
class YorthNameError < YorthError;		end
class YorthSyntaxError < YorthError;	end

class YorthData
	attr_reader	:value
	def initialize kind = nil, value = nil
		@kind = kind
		@value = value
	end
	def dup;	Marshal.load(Marshal.dump self)	end
	def to_s;	@value.to_s;						end
	def to_i
		raise YorthTypeError.new("cannot convert #{value.class} #{@value} to an int") unless @value.respond_to? :to_i and @value.to_i.to_s == @value.to_s
		@value.to_i
	end
	def inspect;	[@kind, @value].inspect;		end
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

class YorthArray
	def initialize values = []
		@values = values
	end
# List of closures
	def evaluate strings, enclosure = Closure.new
		while strings.include?(',')
			comma = strings.index(',')
			strings.slice! comma
			item = Closure.new(strings.slice!(0,comma).reverse, enclosure)
			item.parse!
			@values << item.apply(Closure.new, :block)
		end
		item = Closure.new(strings.reverse, enclosure)
		item.parse!
		@values << item.apply(Closure.new, :block)
	end
	def to_s;		@values.to_s;		end
	def to_a;		@values;			end
	def inspect;	@values.inspect;	end
	def + other
		raise YorthTypeError.new("cannot add array #{@values.inspect} and #{other.class} #{other}") unless other.is_a? YorthArray
		YorthArray.new(@values + other.to_a)
	end
end

class YorthString
	def initialize value;	@value = value.to_s				end
	def dup;				YorthString.new @value			end
	def inspect;			@value.inspect					end
	def to_s;				@value							end
	def to_i;	@value.to_i if @value.to_i.to_s == @value	end
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
	def to_s;		@code.to_s;							end
	def inspect;	[@code.reverse, @scope].inspect;	end
	def terminates;	@code == [];						end
	def dup caller = Closure.new([], nil)
		Closure.new(Marshal.load(Marshal.dump(@code)), @enclosure, caller)
	end

	def has? word
		return true unless @scope[word].nil?
		return false if @enclosure.nil?
		@enclosure.has? word
	end
	def resolve word
		raise YorthNameError.new("unbound variable #{word.inspect}") if @scope[word].value.nil? unless @scope[word].nil?
		return @scope[word].value unless @scope[word].nil?
		return nil if @enclosure.nil?
		@enclosure.resolve word
	end
	def declare word
		@scope[word] = YorthData.new
		nil
	end
	def unassign word
		@scope[word] = nil			unless @scope[word].nil?
		@enclosure.unassign word	unless @enclosure.nil?
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
			libtype = library.split('.')[-1]
			if libtype == "wye"
				file = []
				begin
					File.open(library).each do |line|
						code  = line.split
						file += code unless code[0] == "//"
					end
					puts "'#{library}' loaded"
				rescue Errno::ENOENT
					puts "'#{arg}' does not exist"
				end
				begin
					evaluate file
				rescue YorthError => error
					puts "#{error.class}: #{error}"
				end
			elsif libtype == "wyl"
				file  = []
				pairs = []
				input = ""
				begin
					i = 0
					File.open(library).each do |line|
						code = line.split
						if code[0] == "<="
							file.push(code[1..-1])
							input   = code[1..-1]
						elsif code[0] == "=>"
							pairs[i]     = line[3..-1]
							input        = nil
							i           += 1
						end
					end
					puts "'#{library}' loaded"
				rescue Errno::ENOENT
					puts "'#{arg}' does not exist"
				end
				begin
					verify(file, pairs)
				rescue YorthError => error
					puts "#{error.class}: #{error}"
				end
			else
				puts "'#{library}' is a .#{libtype} file, not a .wye or .wyl file."
			end
		end
		nil
	end

	def interpret
		puts "yorth interpreter initialized"
		begin
			evaluate Readline.readline("<= ", true).chomp.split
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
			when '{'	then pos_f << i
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
			when '['	then pos_a << i
			when ']'
				raise YorthArgumentError.new("non-opened array") if pos_a.nil? or pos_a == []
				beginpoint = pos_a.pop
				if pos_f == []
					beginning = code.shift(beginpoint)
					code.shift(1)
					array = YorthArray.new
					array.evaluate(code.shift(i-beginpoint-1), self)
					code.shift(1)
					return beginning + [array] + code
				end
				end
			i += 1
		end
		raise YorthArgumentError.new("non-terminating function")	unless pos_f == []
		raise YorthArgumentError.new("non-terminating array")		unless pos_a == []
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

	def verify(file, pairs, verbose=true)
		tested = 0
		passed = 0
		failed = 0
		file.each do |code|
			@code = code.reverse
			parse!
			until @code == []
				begin
					last = draw :nil
					fileout = last.inspect unless last.nil?
				rescue TypeError => error
					raise YorthTypeError.new("#{error} in #{code}")
				end
			end
			@code = pairs[tested].split.reverse
			parse!
			until @code == []
				begin
					last = draw :nil
					pairout = last.inspect unless last.nil?
				rescue TypeError => error
					raise YorthTypeError.new("#{error} in #{code}")
				end
			end
			if fileout != pairout then
				puts "Evaluated      #{code.join(' ')}"
				puts "Expected       #{pairout}"
				puts "Got            #{fileout}"
				puts "TEST FAILED."
				failed += 1
				tested += 1
			else
				if verbose
					puts "Evaluated      #{code.join(' ')}"
					puts "Got            #{fileout}" unless pairs[tested].strip == ""
					puts "Test passed." unless pairs[tested].strip == ""
				end
				passed += 1 unless pairs[tested].strip == ""
				tested += 1
			end
		end
		puts "#{failed} failures in #{failed+passed} tests (#{tested} instructions)."
	end

	def apply(caller = Closure.new, *args)
		function = dup caller
		result = function.draw args until function.terminates
		result
	end
	def eval item, *args
		args = args.flatten.uniq
		return item if args.include? :block or not item.is_a? Closure
		item.apply self
	end
	
	def draw *args
		args = args.flatten.uniq
		word = @code.pop
		if word.respond_to? :to_i and word.to_i.to_s == word.to_s	then word.to_i
		elsif word.is_a? YorthString or word.is_a? YorthArray		then word
		elsif word.is_a? Closure									then eval(word, args)
		elsif has? word												then eval(resolve(word), args)
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
		when 'def'		then name = @code.pop; declare name; assign(name, @caller.draw(:block,args))
		when 'del'		then unassign @code.pop
		when 'false'	then false
		when 'inspect'	then self
		when 'let'		then declare @code.pop
		when 'load'		then load @code.pop
		when 'get'		then name = @code.pop; declare name; assign(name, @caller.draw(args))
		when 'nil'		then nil
		when 'not'		then not draw
		when 'or'		then t1 = draw; t2 = draw; t1 or t2
		when 'pop'		then @caller.draw args
		when 'set'		then assign(@code.pop, draw(args))
		when 'setf'		then assign(@code.pop, draw(:block,args))
		when 'true'		then true
		when ".."
			item = draw :block
			puts "#{item.class} #{item.inspect}"
		when 'if'
			condition = draw :block
			whentrue  = draw :block
			whenfalse = draw :block
			if eval(condition)
				eval(whentrue, args)
			else
				eval(whenfalse, args)
			end
		when 'while'
			condition  = draw :block
			statements = draw :block
			while eval condition
				result = eval statements
			end
			result
		when 'iter'
			initial    = draw :block
			condition  = draw :block
			iterate    = draw :block
			statements = draw :block
			eval(initial)
			while eval(condition)
				result = eval(statements)
				eval(iterate)
			end
			result
		when 'enum'
			statements = draw :block
			list       = draw
			result     = []
			list.to_a.each do |item|
				@code.unshift(item)
				result << eval(statements)
			end
			result.compact
		else raise YorthNameError.new("undefined word #{word.inspect}")
		end
		end
	end
end

$libpath = if RUBY_PLATFORM.downcase.include? "linux"	then [".",	"/usr/share/yorth/lib",	"/usr/lib/yorth/**",	"~/.local/share/yorth/lib"	"~/.yorth/lib/**"]
		elsif RUBY_PLATFORM.downcase.include? "darwin"	then [".",	"/usr/share/yorth/lib",	"/usr/lib/yorth/**",	"~/Library/yorth"			"~/.yorth/lib/**"]
		elsif RUBY_PLATFORM.downcase.include? "win"		then [".",	"/Program Files/yorth/lib/**", 					"%APPDATA%/yorth/**",		"~/.yorth/lib/**"]
														else [".",																				"~/.yorth/lib/**"]
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
