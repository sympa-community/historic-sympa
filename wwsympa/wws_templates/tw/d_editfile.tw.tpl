<!-- RCS Identication ; $Revision$ ; $Date$ -->

[IF url]
<H1>[path] ��ñ���s��</H1>
[ELSIF directory]
<H1>[path] �ؿ����s��</H1>
[ELSE]
<H1>[path] ��󪺽s��</H1>
    �Ҧ���: [doc_owner] <BR>
    �̫��s: [doc_date] <BR>
    �y�z: [desc] <BR><BR>
<H3><A HREF="[path_cgi]/d_read/[list]/[father]"> <IMG ALIGN="bottom"  src="[father_icon]"> ���W�@�ťؿ�</A></H3>
[ENDIF]
    �Ҧ���: [doc_owner] <BR>
    �̫��s: [doc_date] <BR>
    �y�z: [desc] <BR><BR>
<H3><A HREF="[path_cgi]/d_read/[list]/[escaped_father]"> <IMG ALIGN="bottom"  src="[father_icon]" BORDER="0"> ���W�@�ťؿ� </A></H3>


<TABLE CELLSPACING=15>

  [IF !directory]
  <TR>
  <form method="post" ACTION="[path_cgi]" ENCTYPE="multipart/form-data">
  <TD ALIGN="right" VALIGN="bottom">
  [IF url]
  <B> �]�w��ñ���} </B><BR> 
  <input name="url" VALUE="[url]">
  [ELSE]
  <B> �αz�������N��� [path] </B><BR> 
  [ENDIF]
  <input type="file" name="uploaded_file">
  </TD>
  <TD ALIGN="left" VALIGN="bottom"> 
  [IF url]
  <input type="submit" value="�ק�" name="action_d_overwrite">
  [ELSE]
  <input type="submit" value="�o��" name="action_d_overwrite">
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
  <B> ��ؿ� [path] �i��y�z </B></BR>
  [ELSE]
  <B> ���� [path] �i��y�z </B></BR>
  [ENDIF]
  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
  <INPUT TYPE="hidden" NAME="path" VALUE="[path]">
  <INPUT TYPE="hidden" NAME="serial" VALUE="[serial_desc]">
  <INPUT TYPE="hidden" NAME="action" VALUE="d_describe">
  <INPUT SIZE=50 MAXLENGTH=100 NAME="content" VALUE="[desc]">
  </TD>
  <TD ALIGN="left" VALIGN="bottom">
  <INPUT SIZE=50 MAXLENGTH=100 TYPE="submit" NAME="action_d_describe" VALUE="����">
  </TD>
  </FORM>
  </TR>

</TABLE>
<BR>
<BR>

[IF !url]
[IF textfile]
  <FORM ACTION="[path_cgi]" METHOD="POST">
  <B> �s���� [path]</B><BR>
  <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
  <INPUT TYPE="hidden" NAME="path" VALUE="[path]">
  <INPUT TYPE="hidden" NAME="serial" VALUE="[serial_file]">
  <TEXTAREA NAME="content" COLS=80 ROWS=25>
[INCLUDE filepath]
  </TEXTAREA><BR>
  <INPUT TYPE="submit" NAME="action_d_savefile" VALUE="�o��">
  </FORM>
[ENDIF]
[ENDIF]




