<!-- RCS Identication ; $Revision$ ; $Date$ -->

<FORM ACTION="[path_cgi]" METHOD=POST>
<TABLE WIDTH="100%" BORDER=0>
<TR><TH BGCOLOR="[dark_color]">
<FONT COLOR="[bg_color]">Information abonn�</FONT>
</TH></TR><TR><TD>
<INPUT TYPE="hidden" NAME="previous_action" VALUE=[previous_action]>
<INPUT TYPE="hidden" NAME="list" VALUE="[list]">
<INPUT TYPE="hidden" NAME="email" VALUE="[current_subscriber->escaped_email]">
<DL>
<DD>E-mail : <INPUT NAME="new_email" VALUE="[current_subscriber->escaped_email]" SIZE="25">
<DD>Nom : <INPUT NAME="gecos" VALUE="[current_subscriber->gecos]" SIZE="25">
<DD>Abonn� depuis : [current_subscriber->date]
<DD>Derni�re mise � jour : [current_subscriber->update_date]
<DD>R�ception : <SELECT NAME="reception">
		  [FOREACH r IN reception]
		    <OPTION VALUE="[r->NAME]" [r->selected]>[r->description]
		  [END]
	        </SELECT>

<DD>Visibilit� : [current_subscriber->visibility]
<DD>Langue : [current_subscriber->lang]
<DD><INPUT TYPE="submit" NAME="action_set" VALUE="Mise � jour">
<INPUT TYPE="submit" NAME="action_del" VALUE="D�sabonner l'usager">
<INPUT TYPE="checkbox" NAME="quiet"> sans pr�venir
</DL>
</TD></TR>
[IF current_subscriber->bounce]
<TR><TH BGCOLOR="[error_color]">
<FONT COLOR="[bg_color]">Adresse en erreur</FONT>
</TH></TR><TR><TD>
<DL>
<DD>Type d'erreur : [current_subscriber->bounce_status] ([current_subscriber->bounce_code])
<DD>Nombre de retour : [current_subscriber->bounce_count]
<DD>P�riode : from [current_subscriber->first_bounce] to [current_subscriber->last_bounce]
<DD><A HREF="[path_cgi]/viewbounce/[list]/[current_subscriber->escaped_email]">Derni�re erreur</A>
<DD><INPUT TYPE="submit" NAME="action_resetbounce" VALUE="Effacer les erreurs">
</DL>
</TD></TR>
[ENDIF]
</TABLE>
</FORM>



