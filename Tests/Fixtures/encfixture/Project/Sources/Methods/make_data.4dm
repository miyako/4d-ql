//%attributes = {"invisible":true}
// Fills the fixture tables. [Secret] and [EmptySecret] are encryptable;
// [EmptySecret] is left without records on purpose.
var $i : Integer
var $e : 4D.Entity
var $b : Blob
For ($i; 1; 5)
	$e:=ds.Plain.new()
	$e.name:="plain-"+String($i)
	$e.note:="PLAIN-MARKER "*(1+($i*10))
	$e.save()
	$e:=ds.Secret.new()
	$e.name:="SECRET-NAME-"+String($i)
	$e.note:="SECRET-MARKER "*(1+($i*10))
	TEXT TO BLOB("SECRET-BLOB "*200; $b; UTF8 text without length)
	$e.payload:=$b
	$e.save()
End for
LOG EVENT(Into system standard outputs; "plain="+String(ds.Plain.all().length)+" secret="+String(ds.Secret.all().length)+"\n")
QUIT 4D
