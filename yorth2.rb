def draw
	word = $code.pop
	if word.to_i.to_s == word then
		return word.to_i
	end
	case word
	when '+'	then draw + draw
	when '-'	then draw - draw
	when '*'	then draw * draw
	when '/'	then draw / draw
	when '.'	then puts draw
	when 'bye'	then exit
	else
		raise "#{word} is not a valid word."
	end
end

while true
	print "<= "
	$code = gets.chomp.split.reverse
	until $code == []
		puts "=> #{draw}"
	end
end


def expo(base, exponent)
answer = base
while exponent >1
	answer = answer * base
	exponent = exponent - 1
end
return answer
end