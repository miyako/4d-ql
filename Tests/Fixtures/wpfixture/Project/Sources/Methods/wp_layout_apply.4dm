#DECLARE($doc : Object; $edit : Object)
var $target; $item; $stop; $default : Object
var $tabs; $paragraphs : Collection
Case of
	: ($edit.action="columns")
		$target:=$doc
		If ($edit.index>0)
			$target:=WP Get section($doc; $edit.index)
		End if
		If (OB Is defined($edit; "count"))
			If ($edit.count=Null)
				WP RESET ATTRIBUTES($target; wk column count)
			Else
				WP SET ATTRIBUTES($target; wk column count; $edit.count)
			End if
		End if
		If (OB Is defined($edit; "gap"))
			If ($edit.gap=Null)
				WP RESET ATTRIBUTES($target; wk column spacing)
			Else
				WP SET ATTRIBUTES($target; wk column spacing; $edit.gap)
			End if
		End if
	: ($edit.action="tabs")
		$paragraphs:=WP Get elements(WP Get body($doc); wk type paragraph)
		For each ($item; $edit.paragraphs)
			$tabs:=New collection()
			For each ($stop; $item.stops)
				$tabs.push(New object(wk offset; $stop.position; wk type; $stop.type; wk leading; $stop.leader))
			End for each
			$default:=$item.default
			WP SET ATTRIBUTES($paragraphs[$item.index]; wk tabs; $tabs; wk tab default; New object(wk offset; $default.position; wk type; $default.type; wk leading; $default.leader))
		End for each
	: ($edit.action="reset")
		$paragraphs:=WP Get elements(WP Get body($doc); wk type paragraph)
		For each ($item; $edit.paragraphs)
			WP RESET ATTRIBUTES($paragraphs[$item.index]; wk tabs; wk tab default)
		End for each
	: ($edit.action="insert")
		WP SET TEXT(WP Text range(WP Get body($doc); $edit.point; $edit.point); Char(9); wk replace)
End case
