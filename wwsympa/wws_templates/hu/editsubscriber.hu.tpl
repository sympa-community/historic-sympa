<!-- RCS Identication ; $Revision$ ; $Date$ -->

<FORM ACTION="[path_cgi]" METHOD=POST>
<TABLE WIDTH="100%" BORDER=0>
<TR><TH BGCOLOR="[dark_color]">
<FONT COLOR="[bg_color]">Inform�ci�k a listatagokr�l</FONT>
</TH></TR><TR><TD>
<INPUT TYPE="hidden" NAME="previous_action" VALUE=[previous_action]>
<INPUT TYPE="hidden" NAME="list" VALUE="[list]">
<INPUT TYPE="hidden" NAME="email" VALUE="[current_subscriber->escaped_email]">
<DL>
<DD>E-mail: <INPUT NAME="new_email" VALUE="[current_subscriber->email]" SIZE="25">
<DD>N�v: <INPUT NAME="gecos" VALUE="current_[subscriber->gecos]" SIZE="25">
<DD>[current_subscriber->date] �ta listatag
<DD>Utols� m�dos�t�s: [current_subscriber->update_date]
<DD>K�ld�si m�d: <SELECT NAME="reception">
		  [FOREACH r IN reception]
		    <OPTION VALUE="[r->NAME]" [r->selected]>[r->description]
		  [END]
	        </SELECT>

<DD>Nyilv�noss�g: [current_subscriber->visibility]
<DD>Nyelv: [current_subscriber->lang]
<DD><INPUT TYPE="submit" NAME="action_set" VALUE="Friss�t">
<INPUT TYPE="submit" NAME="action_del" VALUE="A tag t�rl�se">
<INPUT TYPE="checkbox" NAME="quiet"> nincs �rtes�t�s
</DL>
</TD></TR>
[IF current_subscriber->bounce]
<TR><TH BGCOLOR="[error_color]">
<FONT COLOR="[bg_color]">Visszapattan� c�mek</FONT>
</TD></TR><TR><TD>
<DL>
<DD>�llapot: [current_subscriber->bounce_status] ([current_subscriber->bounce_code])
<DD>Visszak�ld�sek: [current_subscriber->bounce_count]
<DD>Id�szak: [current_subscriber->first_bounce]-t�l/t�l [current_subscriber->last_bounce]-ig
<DD><A HREF="[path_cgi]/viewbounce/[list]/[current_subscriber->escaped_email]">Mutasd az utols�t</A>
<DD><INPUT TYPE="submit" NAME="action_resetbounce" VALUE="Hib�k t�rl�se">
</DL>
</TD></TR>
[ENDIF]
</TABLE>
</FORM>
