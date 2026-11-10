var $e : Object
For each ($e; Last errors)
	wp_log("ERROR "+String($e.errCode)+" "+$e.message+" ("+Error method+":"+String(Error line)+")")
End for each
