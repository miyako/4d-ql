var wpBookmarkErrors : Collection
var $error : Object
For each ($error; Last errors)
	wpBookmarkErrors.push(New object("code"; $error.errCode; "message"; $error.message))
End for each
