<!-- RCS Identication ; $Revision$ ; $Date$ -->

<FORM ACTION="[path_cgi]" METHOD=POST>
<TABLE WIDTH="100%" BORDER=0>
<TR><TH BGCOLOR="[dark_color]">
<FONT COLOR="[bg_color]">Tilaaja tiedot</FONT>
</TH></TR><TR><TD>
<INPUT TYPE="hidden" NAME="previous_action" VALUE=[previous_action]>
<INPUT TYPE="hidden" NAME="list" VALUE="[list]">
<INPUT TYPE="hidden" NAME="email" VALUE="[current_subscriber->escaped_email]">
<DL>
<DD>Email : <INPUT NAME="new_email" VALUE="[current_subscriber->email]" SIZE="25">
<DD>Nimi : <INPUT NAME="gecos" VALUE="[current_subscriber->gecos]" SIZE="25">
<DD>Tilauksen alkamispvm [current_subscriber->date]
<DD>Viim. p�ivitys : [current_subscriber->update_date]
<DD>Vastaanotto : <SELECT NAME="reception">
		  [FOREACH r IN reception]
		    <OPTION VALUE="[r->NAME]" [r->selected]>[r->description]
		  [END]
	        </SELECT>

<DD>N�kyvyys : [current_subscriber->visibility]
<DD>Kieli : [current_subscriber->lang]
<DD><INPUT TYPE="submit" NAME="action_set" VALUE="P�ivit�">
<INPUT TYPE="submit" NAME="action_del" VALUE="Poista k�ytt�j�n tilaus">
<INPUT TYPE="checkbox" NAME="quiet"> hiljainen
</DL>
</TD></TR>
[IF current_subscriber->bounce]
<TR><TH BGCOLOR="[error_color]">
<FONT COLOR="[bg_color]">Palatut viestit osoitteeseen</FONT>
</TH></TR><TR><TD>
<DL>
<DD>Tilanne : [current_subscriber->bounce_status] ([current_subscriber->bounce_code])
<DD>Palanneiden viestien m��r� : [current_subscriber->bounce_count]
<DD>Ajanjakso : l�hett�j� [current_subscriber->first_bounce] vastaanottaja [current_subscriber->last_bounce]
<DD><A HREF="[path_cgi]/viewbounce/[list]/[current_subscriber->escaped_email]">Katso viimeksi palannut viesti</A>
<DD><INPUT TYPE="submit" NAME="action_resetbounce" VALUE="Tyhj�� virheet">
</DL>
</TD></TR>
[ENDIF]
</TABLE>
</FORM>



