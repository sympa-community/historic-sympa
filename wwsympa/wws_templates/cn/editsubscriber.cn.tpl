<!-- RCS Identication ; $Revision$ ; $Date$ -->

<FORM ACTION="[path_cgi]" METHOD=POST>
<TABLE WIDTH="100%" BORDER=0>
<TR><TH BGCOLOR="[dark_color]">
<FONT COLOR="[bg_color]">�ʵݱ�������Ϣ</FONT>
</TH></TR><TR><TD>
<INPUT TYPE="hidden" NAME="previous_action" VALUE=[previous_action]>
<INPUT TYPE="hidden" NAME="list" VALUE="[list]">
<INPUT TYPE="hidden" NAME="email" VALUE="[current_subscriber->escaped_email]">
<DL>
<DD>Email: <A HREF="mailto:[current_subscriber->email]">[subscriber->email]</A>
<DD>����: <INPUT NAME="gecos" VALUE="[current_subscriber->gecos]" SIZE="25">
<DD>����ʱ��: [current_subscriber->date]
<DD>����: <SELECT NAME="reception">
		  [FOREACH r IN reception]
		    <OPTION VALUE="[r->NAME]" [r->selected]>[r->description]
		  [END]
	        </SELECT>

<DD>�ɼ���: [current_subscriber->visibility]
<DD>����: [current_subscriber->lang]
<DD><INPUT TYPE="submit" NAME="action_set" VALUE="����">
<INPUT TYPE="submit" NAME="action_del" VALUE="ȡ���û��Ķ���">
<INPUT TYPE="checkbox" NAME="quiet"> ����
</DL>
</TD></TR>
[IF current_subscriber->bounce]
<TR><TH BGCOLOR="[error_color]">
<FONT COLOR="[bg_color]">���ŵ�ַ</FONT>
</TD></TR><TR><TD>
<DL>
<DD>״̬: [current_subscriber->bounce_status] ([current_subscriber->bounce_code])
<DD>���ż���: [current_subscriber->bounce_count]
<DD>ʱ��: �� [current_subscriber->first_bounce] �� [current_subscriber->last_bounce]
<DD><A HREF="[path_cgi]/viewbounce/[list]/[current_subscriber->escaped_email]">�鿴��������</A>
<DD><INPUT TYPE="submit" NAME="action_resetbounce" VALUE="���ô������">
</DL>
</TD></TR>
[ENDIF]
</TABLE>
</FORM>



