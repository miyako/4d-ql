//%attributes = {"invisible":true}
// --user-param = absolute path of a closed data file to encrypt in place.
var $path; $result : Text
Get database parameter(User param value; $path)
var $archive : 4D.Folder
$archive:=Folder(Get 4D folder(Database folder); fk platform path).folder("archive")
$archive.create()
$result:=Encrypt data file(Structure file; Convert path POSIX to system($path); "correct horse battery staple"; $archive.platformPath)
LOG EVENT(Into system standard outputs; "OK="+String(OK)+" archive="+$result+"\n")
QUIT 4D
