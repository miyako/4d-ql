var wpWebErrors : Collection
var $error : Object
For each ($error; Last errors)
	wpWebErrors.push(New object("code"; $error.errCode; "message"; $error.message; "method"; Error method; "line"; Error line))
	wp_log("NATIVE ERROR "+String($error.errCode)+" "+$error.message)
End for each
