var $out; $title; $source; $format; $left; $center; $right : Text
var $area; $i; $hide; $width; $repeat; $height; $ops; $line; $color : Integer
var $blob : Blob
var $info; $col : Object
Get database parameter(User param value; $out)
$blob:=File($out+".4qr").getContent()
$area:=QR New offscreen area
QR BLOB TO REPORT($area; $blob)
$info:={kind: QR Get report kind($area); table: QR Get report table($area); columns: New collection; rows: New collection; unit: QR Get document property($area; 2)}
For ($i; 1; QR Count columns($area))
	QR GET INFO COLUMN($area; $i; $title; $source; $hide; $width; $repeat; $format)
	$col:={title: $title; source: $source; hidden: $hide; width: $width; repeated: $repeat; format: $format; titleSize: QR Get text property($area; $i; -1; 2); titleBold: QR Get text property($area; $i; -1; 3); titleColor: QR Get text property($area; $i; -1; 6); titleBackground: QR Get text property($area; $i; -1; 8); titleJustification: QR Get text property($area; $i; -1; 7)}
	QR GET TOTALS DATA($area; $i; -3; $ops; $title)
	$col.totalOperators:=$ops
	$col.totalText:=$title
	QR GET BORDERS($area; $i; -1; 8; $line; $color)
	$col.bottomBorderThickness:=$line
	$col.bottomBorderColor:=$color
	$info.columns.push($col)
End for
QR GET HEADER AND FOOTER($area; 1; $left; $center; $right; $height)
$info.header:={left: $left; center: $center; right: $right; height: $height}
QR GET HEADER AND FOOTER($area; 2; $left; $center; $right; $height)
$info.footer:={left: $left; center: $center; right: $right; height: $height}
ARRAY REAL($cols; 0)
ARRAY REAL($orders; 0)
QR GET SORTS($area; $cols; $orders)
$info.sortColumns:=New collection
$info.sortOrders:=New collection
For ($i; 1; Size of array($cols))
	$info.sortColumns.push($cols{$i})
	$info.sortOrders.push($orders{$i})
End for
For ($i; -3; -1)
	$info.rows.push(QR Get info row($area; $i))
End for
File($out+".json").setText(JSON Stringify($info; *))
LOG EVENT(Into system standard outputs; JSON Stringify($info; *)+"\n")
QR DELETE OFFSCREEN AREA($area)
QUIT 4D
