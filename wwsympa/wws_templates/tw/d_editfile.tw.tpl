<!-- RCS Identication ; $Revision$ ; $Date$ -->

[IF url]
<H1>[path] 書簽的編修</H1>
[ELSIF directory]
<H1>[path] 目錄的編修</H1>
[ELSE]
<H1>[path] 文件的編修</H1>
    所有者: [doc_owner] <BR>
    最後更新: [doc_date] <BR>
    描述: [desc] <BR><BR>
<H3><A HREF="[path_cgi]/d_read/[list]/[father]"> <IMG ALIGN="bottom"  src="[father_icon]"> 轉到上一級目錄</A></H3>
[ENDIF]
    所有者: [doc_owner] <BR>
    最後更新: [doc_date] <BR>
    描述: [desc] <BR><BR>
<H3><A HREF="[path_cgi]/d_read/[list]/[escaped_father]"> <IMG ALIGN="bottom"  src="[father_icon]" BORDER="0"> 轉到上一級目錄 </A></H3>


<TABLE CELLSPACING=15>

  [IF !directory]
  <TR>
  <form method="post" ACTION="[path_cgi]" ENCTYPE="multipart/form-data">
  <TD ALIGN="right" VALIGN="bottom">
  [IF url]
  <B> 設定書簽網址 </B><BR> 
  <input name="url" VALUE="[url]">
  [ELSE]
  <B> 用您的文件取代文件 [path] </B><BR> 
  [ENDIF]
  <input type="file" name="uploaded_file">
  </TD>
  <TD ALIGN="left" VALIGN="bottom"> 
  [IF url]
  <input type="submit" value="修改" name="action_d_overwrite">
  [ELSE]
  <input type="submit" value="發布" name="action_d_overwrite">
  [ENDIF]
  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
  <INPUT TYPE="hidden" NAME="path" VALUE="[path]">
  <INPUT TYPE="hidden" NAME="serial" VALUE="[serial_file]">
  </TD>
  </form>
  </TR>

  <TR>
  <FORM ACTION="[path_cgi]" METHOD="POST">
  <TD ALIGN="right" VALIGN="bottom">
  [IF directory]
  <B> 對目錄 [path] 進行描述 </B></BR>
  [ELSE]
  <B> 對文件 [path] 進行描述 </B></BR>
  [ENDIF]
  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
  <INPUT TYPE="hidden" NAME="path" VALUE="[path]">
  <INPUT TYPE="hidden" NAME="serial" VALUE="[serial_desc]">
  <INPUT TYPE="hidden" NAME="action" VALUE="d_describe">
  <INPUT SIZE=50 MAXLENGTH=100 NAME="content" VALUE="[desc]">
  </TD>
  <TD ALIGN="left" VALIGN="bottom">
  <INPUT SIZE=50 MAXLENGTH=100 TYPE="submit" NAME="action_d_describe" VALUE="應用">
  </TD>
  </FORM>
  </TR>

</TABLE>
<BR>
<BR>

[IF !url]
[IF textfile]
  <FORM ACTION="[path_cgi]" METHOD="POST">
  <B> 編輯文件 [path]</B><BR>
  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
  <INPUT TYPE="hidden" NAME="path" VALUE="[path]">
  <INPUT TYPE="hidden" NAME="serial" VALUE="[serial_file]">
  <TEXTAREA NAME="content" COLS=80 ROWS=25>
[INCLUDE filepath]
  </TEXTAREA><BR>
  <INPUT TYPE="submit" NAME="action_d_savefile" VALUE="發布">
  </FORM>
[ENDIF]
[ENDIF]




