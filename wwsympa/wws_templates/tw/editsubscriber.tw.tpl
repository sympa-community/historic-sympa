<!-- RCS Identication ; $Revision$ ; $Date$ -->

<FORM ACTION="[path_cgi]" METHOD=POST>
<TABLE WIDTH="100%" BORDER=0>
<TR><TH BGCOLOR="[dark_color]">
<FONT COLOR="[bg_color]"> Mailing List �q�\�̰T��</FONT>
</TH></TR><TR><TD>
<INPUT TYPE="hidden" NAME="previous_action" VALUE=[previous_action]>
<INPUT TYPE="hidden" NAME="list" VALUE="[list]">
<INPUT TYPE="hidden" NAME="email" VALUE="[current_subscriber->escaped_email]">
<DL>
<DD>Email: <A HREF="mailto:[current_subscriber->email]">[subscriber->email]</A>
<DD>�W�r: <INPUT NAME="gecos" VALUE="[current_subscriber->gecos]" SIZE="25">
<DD>�q�\�ɶ�: [current_subscriber->date]
<DD>����: <SELECT NAME="reception">
		  [FOREACH r IN reception]
		    <OPTION VALUE="[r->NAME]" [r->selected]>[r->description]
		  [END]
	        </SELECT>

<DD>�i����: [current_subscriber->visibility]
<DD>�y��: [current_subscriber->lang]
<DD><INPUT TYPE="submit" NAME="action_set" VALUE="��s">
<INPUT TYPE="submit" NAME="action_del" VALUE="�����Τ᪺�q�\">
<INPUT TYPE="checkbox" NAME="quiet"> �w�R
</DL>
</TD></TR>
[IF current_subscriber->bounce]
<TR><TH BGCOLOR="[error_color]">
<FONT COLOR="[bg_color]">�h�H�a�}</FONT>
</TD></TR><TR><TD>
<DL>
<DD>���A: [current_subscriber->bounce_status] ([current_subscriber->bounce_code])
<DD>�h�H�p��: [current_subscriber->bounce_count]
<DD>�ɶ�: �q [current_subscriber->first_bounce] �� [current_subscriber->last_bounce]
<DD><A HREF="[path_cgi]/viewbounce/[list]/[current_subscriber->escaped_email]">�d�ݳ̫᪺�h�H</A>
<DD><INPUT TYPE="submit" NAME="action_resetbounce" VALUE="���m���~�p��">
</DL>
</TD></TR>
[ENDIF]
</TABLE>
</FORM>



