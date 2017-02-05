import Data.Char (isDigit)
data YorthData = YNil
    | YInt Integer
    | YOpAdd
    | YOpSub
    | YOpMul
    | YOpDiv
    | YError String
    deriving (Show, Eq, Ord)
data Closure = DoneToken
    | Closure [YorthData] Closure [(YorthData, [Closure])] Closure
	deriving (Show, Eq, Ord)
empty_closure = (Closure [] empty_closure [] empty_closure)
parse :: Closure -> [String] -> Closure -> Closure
parse enclosure inputs caller = (Closure (stacks inputs) enclosure [] caller)
    where stacks [] = []
    	  stacks (input:is)
		| foldl1 (&&) (map isDigit input) = (YInt (read input)):(stacks is)
   	  	| otherwise (case input of
    			"+" -> YOpAdd
    			"-" -> YOpSub
    			"*" -> YOpMul
    			"/" -> YOpDiv
    			"}" -> YNil
			_ -> YError "Undefined token"
    		):(stacks is)
step :: Closure -> (YorthData, Closure)
step (Closure [] enclosure scope caller) = (YNil, DoneToken)
step (Closure (stack:ss) enclosure scope caller) = (YNil, empty_closure)