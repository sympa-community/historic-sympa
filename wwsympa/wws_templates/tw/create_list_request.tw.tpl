<!-- RCS Identication ; $Revision$ ; $Date$ -->


<FORM ACTION="[path_cgi]" METHOD=POST>

<P>
<TABLE>
 <TR>
   <TD NOWRAP><B> Mailing List �W�r:</B></TD>
   <TD><INPUT TYPE="text" NAME="listname" SIZE=30 VALUE="[saved->listname]"></TD>
   <TD><img src="[icons_url]/unknown.png" alt=" Mailing List �W�F�`�N�A���O�����a�}!"></TD>
 </TR>
 
 <TR>
   <TD NOWRAP><B>�Ҧ���:</B></TD>
   <TD><I>[user->email]</I></TD>
   <TD><img src="[icons_url]/unknown.png" alt="�z�O�o�� Mailing List ��Privilege�Ҧ���"></TD>
 </TR>

 <TR>
   <TD valign=top NOWRAP><B> Mailing List ����: </B></TD>
   <TD>
     <MENU>
  [FOREACH template IN list_list_tpl]
     <INPUT TYPE="radio" NAME="template" Value="[template->NAME]"
     [IF template->selected]
       CHECKED
     [ENDIF]
     > [template->NAME]<BR>
     <BLOCKQUOTE>
     [PARSE template->comment]
     </BLOCKQUOTE>
     <BR>
  [END]
     </MENU>
    </TD>
    <TD valign=top><img src="[icons_url]/unknown.png" alt=" Mailing List �����O�Ѽƶ��]�w�C�i�H�b Mailing List �Ыث�s��Ѽ�"></TD>
 </TR>
 <TR>
   <TD NOWRAP><B>�D�D:</B></TD>
   <TD><INPUT TYPE="text" NAME="subject" SIZE=60 VALUE="[saved->subject]"></TD>
   <TD><img src="[icons_url]/unknown.png" alt="�o�O Mailing List ���D�D"></TD>
 </TR>
 <TR>
   <TD NOWRAP><B>���D:</B></TD>
   <TD><SELECT NAME="topics">
	<OPTION VALUE="">--��ܸ��D--
	[FOREACH topic IN list_of_topics]
	  <OPTION VALUE="[topic->NAME]"
	  [IF topic->selected]
	    SELECTED
	  [ENDIF]
	  >[topic->title]
	  [IF topic->sub]
	  [FOREACH subtopic IN topic->sub]
	     <OPTION VALUE="[topic->NAME]/[subtopic->NAME]">[topic->title] / [subtopic->title]
	  [END]
	  [ENDIF]
	[END]
	<OPTION VALUE="other">�䥦
     </SELECT>
   </TD>
   <TD valign=top><img src="[icons_url]/unknown.png" alt="�ؿ����� Mailing List ����"></TD>
 </TR>

 <TR>
   <TD valign=top NOWRAP><B>�y�z:</B></TD>
   <TD><TEXTAREA COLS=60 ROWS=10 NAME="info">[saved->info]</TEXTAREA></TD>
   <TD valign=top><img src="[icons_url]/unknown.png" alt="�X��� Mailing List ���y�z��r"></TD>
 </TR>

 <TR>
   <TD COLSPAN=2 ALIGN="center">
    <TABLE>
     <TR>
      <TD BGCOLOR="[light_color]">
<INPUT TYPE="submit" NAME="action_create_list" VALUE="�T�{�z���ЫؽШD">
      </TD>
     </TR></TABLE>
</TD></TR>
</TABLE>



</FORM>




