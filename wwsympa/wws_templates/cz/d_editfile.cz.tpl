<!-- RCS Identication ; $Revision$ ; $Date$ -->

[IF url]
<H1>�prava z�lo�ky [path]</H1>
[ELSIF directory]
<H1>�prava adres��e [path]</H1>
[ELSE]
<H1>�prava souboru [path]</H1>
[ENDIF]
    Vlastn�k : [doc_owner] <BR>
    Posledn� zm�na : [doc_date] <BR>
    popis : [desc] <BR><BR>
<H3><A HREF="[path_cgi]/d_read/[list]/[escaped_father]"> <IMG ALIGN="bottom"  src="[father_icon]" BORDER="0"> O �rove� v�� </A></H3>

<TABLE CELLSPACING=15>

  [IF !directory]
  <TR>
  <form method="post" ACTION="[path_cgi]" ENCTYPE="multipart/form-data">
  <TD ALIGN="right" VALIGN="bottom">
  [IF url]
  <B> Bookmark URL </B><BR> 
  <input name="url" VALUE="[url]">
  [ELSE]
  <B> Nahradit soubor [path] Va��m souborem </B><BR> 
  <input type="file" name="uploaded_file">
  [ENDIF]
  </TD>
  <TD ALIGN="left" VALIGN="bottom"> 
  [IF url]
  <input type="submit" value="Upravit" name="action_d_savefile">
  [ELSE]
  <input type="submit" value="Publikovat" name="action_d_overwrite">
  [ENDIF]
  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
  <INPUT TYPE="hidden" NAME="path" VALUE="[path]">
  <INPUT TYPE="hidden" NAME="serial" VALUE="[serial_file]">
  </TD>
  </form>
  </TR>
  [ENDIF]

  <TR>
  <FORM ACTION="[path_cgi]" METHOD="POST">
  <TD ALIGN="right" VALIGN="bottom">
  [IF directory]
  <B> Popi�te adres�� [path]</B><BR>
  [ELSE]
  <B> Popi�te soubor [path]</B><BR>
  [ENDIF]
  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
  <INPUT TYPE="hidden" NAME="path" VALUE="[path]">
  <INPUT TYPE="hidden" NAME="serial" VALUE="[serial_desc]">
  <INPUT TYPE="hidden" NAME="action" VALUE="d_describe">
  <INPUT SIZE=50 MAXLENGTH=100 NAME="content" VALUE="[desc]">
  </TD>
  <TD ALIGN="left" VALIGN="bottom">
  <INPUT SIZE=50 MAXLENGTH=100 TYPE="submit" NAME="action_d_describe" VALUE="Pou��t">
  </TD>
  </FORM>
  </TR>

  <TR>
  <FORM ACTION="[path_cgi]" METHOD="POST">
  <TD ALIGN="right" VALIGN="bottom">
  [IF directory]
  <B> P�ejmenovat adres�� [path]</B><BR>
  [ELSE]
  <B> P�ejmenovat soubor [path]</B><BR>
  [ENDIF]
  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
  <INPUT TYPE="hidden" NAME="path" VALUE="[path]">
  <INPUT TYPE="hidden" NAME="serial" VALUE="[serial_desc]">
  <INPUT TYPE="hidden" NAME="action" VALUE="d_rename">
  <INPUT SIZE=50 MAXLENGTH=100 NAME="new_name"></TD>
  <TD ALIGN="left" VALIGN="bottom">
  <INPUT SIZE=20 MAXLENGTH=50 TYPE="submit" NAME="action_d_rename" VALUE="P�ejmenovat">
  </TD>
  </FORM>
  </TR>

</TABLE>
<BR>
<BR>

[IF !url]
[IF textfile]
  <FORM ACTION="[path_cgi]" METHOD="POST">
  <B> Upravit soubor [path]</B><BR>
  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
  <INPUT TYPE="hidden" NAME="path" VALUE="[path]">
  <INPUT TYPE="hidden" NAME="serial" VALUE="[serial_file]">
  <TEXTAREA NAME="content" COLS=80 ROWS=25>
[INCLUDE filepath]
  </TEXTAREA><BR>
  <INPUT TYPE="submit" NAME="action_d_savefile" VALUE="Publikovat">
  </FORM>
[ENDIF]
[ENDIF]




