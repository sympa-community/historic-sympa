<!-- RCS Identication ; $Revision$ ; $Date$ -->

<FORM ACTION="[path_cgi]" METHOD=POST>
<TABLE WIDTH="100%" BORDER=0>
<TR><TH BGCOLOR="[dark_color]">
<FONT COLOR="[bg_color]">Informace o �lenu</FONT>
</TH></TR><TR><TD>
<INPUT TYPE="hidden" NAME="previous_action" VALUE=[previous_action]>
<INPUT TYPE="hidden" NAME="list" VALUE="[list]">
<INPUT TYPE="hidden" NAME="email" VALUE="[current_subscriber->escaped_email]">
<DL>
<DD>Adresa : <INPUT NAME="new_email" VALUE="[current_subscriber->email]" SIZE="25">
<DD>Jm�no : <INPUT NAME="gecos" VALUE="[current_subscriber->gecos]" SIZE="25">
<DD>�lenem od [current_subscriber->date]
<DD>P��jem : <SELECT NAME="reception">
		  [FOREACH r IN reception]
		    <OPTION VALUE="[r->NAME]" [r->selected]>[r->description]
		  [END]
	        </SELECT>

<DD>Viditelnost : [current_subscriber->visibility]
<DD>Jazyk : [current_subscriber->lang]
<DD><INPUT TYPE="submit" NAME="action_set" VALUE="Zm�nit">
<INPUT TYPE="submit" NAME="action_del" VALUE="Odhl�sit u�ivatele">
<INPUT TYPE="checkbox" NAME="quiet"> Potichu
</DL>
</TD></TR>
[IF current_subscriber->bounce]
<TR><TH BGCOLOR="[error_color]">
<FONT COLOR="[bg_color]">Vracej�c� se adresa</FONT>
</TD></TR><TR><TD>
<DL>
<DD>Stav : [current_subscriber->bounce_status] ([current_subscriber->bounce_code])
<DD>Po�et vr�cen�ch zpr�v : [current_subscriber->bounce_count]
<DD>Obdob� : od [current_subscriber->first_bounce] do [current_subscriber->last_bounce]
<DD><A HREF="[path_cgi]/viewbounce/[list]/[current_subscriber->escaped_email]">Zobrazit posledn� vr�cenou zpr�vu</A>
<DD><INPUT TYPE="submit" NAME="action_resetbounce" VALUE="Vynulovat chyby">
</DL>
</TD></TR>
[ENDIF]
</TABLE>
</FORM>
