<!-- RCS Identication ; $Revision$ ; $Date$ -->

<FORM ACTION="[path_cgi]" METHOD=POST>
<TABLE WIDTH="100%" BORDER=0>
<TR><TH BGCOLOR="[dark_color]">
<FONT COLOR="[bg_color]">Abonnenten Information</FONT>
</TH></TR><TR><TD>
<INPUT TYPE="hidden" NAME="previous_action" VALUE=[previous_action]>
<INPUT TYPE="hidden" NAME="list" VALUE="[list]">
<INPUT TYPE="hidden" NAME="email" VALUE="[current_subscriber->escaped_email]">
<DL>
<DD>Email: <INPUT NAME="new_email" VALUE="[current_subscriber->email]" SIZE="25">
<DD>Name: <INPUT NAME="gecos" VALUE="[current_subscriber->gecos]" SIZE="25">
<DD>Abonnent seit [current_subscriber->date]
<DD>Empfang: <SELECT NAME="reception">
		  [FOREACH r IN reception]
		    <OPTION VALUE="[r->NAME]" [r->selected]>[r->description]
		  [END]
	        </SELECT>

<DD>Sichbarkeit: [current_subscriber->visibility]
<DD>Sprache: [current_subscriber->lang]
<DD><INPUT TYPE="submit" NAME="action_set" VALUE="&Auml;ndern">
<INPUT TYPE="submit" NAME="action_del" VALUE="Abonnierung beenden">
<INPUT TYPE="checkbox" NAME="quiet"> Still
</DL>
</TD></TR>
[IF current_subscriber->bounce]
<TR><TH BGCOLOR="[error_color]">
<FONT COLOR="[bg_color]">Unzustellbare Adresse</FONT>
</TD></TR><TR><TD>
<DL>
<DD>Zustand: [current_subscriber->bounce_status] ([current_subscriber->bounce_code])
<DD>Anzahl: [current_subscriber->bounce_count]
<DD>Zeitraum: from [current_subscriber->first_bounce] to [current_subscriber->last_bounce]
<DD><A HREF="[path_cgi]/viewbounce/[list]/[current_subscriber->escaped_email]">Letzte abgewiesene Nachricht anschauen</A>
<DD><INPUT TYPE="submit" NAME="action_resetbounce" VALUE="Zur&uuml;cksetzen">
</DL>
</TD></TR>
[ENDIF]
</TABLE>
</FORM>



