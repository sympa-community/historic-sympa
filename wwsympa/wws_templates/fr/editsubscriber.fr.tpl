<FORM ACTION="[path_cgi]" METHOD=POST>
<TABLE WIDTH="100%" BORDER=0>
<TR><TH BGCOLOR="--DARK_COLOR--">
<FONT COLOR="--BG_COLOR--">Information abonn�</FONT>
</TH></TR><TR><TD>
<INPUT TYPE="hidden" NAME="previous_action" VALUE=[previous_action]>
<INPUT TYPE="hidden" NAME="list" VALUE="[list]">
<INPUT TYPE="hidden" NAME="email" VALUE="[subscriber->escaped_email]">
<DL>
<DD>Email : <INPUT NAME="new_email" VALUE="[subscriber->email]" SIZE="25">
<DD>Nom : <INPUT NAME="gecos" VALUE="[subscriber->gecos]" SIZE="25">
<DD>Abonn� depuis : [subscriber->date]
<DD>R�ception : <SELECT NAME="reception">
		  [FOREACH r IN reception]
		    <OPTION VALUE="[r->NAME]" [r->selected]>[r->description]
		  [END]
	        </SELECT>

<DD>Visibilit� : [subscriber->visibility]
<DD>Langue : [subscriber->lang]
<DD><INPUT TYPE="submit" NAME="action_set" VALUE="Mise � jour">
<INPUT TYPE="submit" NAME="action_del" VALUE="D�sabonner l'usager">
<INPUT TYPE="checkbox" NAME="quiet"> sans pr�venir
</DL>
</TD></TR>
[IF subscriber->bounce]
<TR><TH BGCOLOR="--ERROR_COLOR--">
<FONT COLOR="--BG_COLOR--">Address en erreur</FONT>
</TD></TR><TR><TD>
<DL>
<DD>Type d'erreur : [subscriber->bounce_status] ([subscriber->bounce_code])
<DD>Nombre de retour : [subscriber->bounce_count]
<DD>P�riode : from [subscriber->first_bounce] to [subscriber->last_bounce]
<DD><A HREF="[path_cgi]/viewbounce/[list]/[subscriber->escaped_email]">Derni�re erreur</A>
<DD><INPUT TYPE="submit" NAME="action_resetbounce" VALUE="Effacer les erreurs">
</DL>
</TD></TR>
[ENDIF]
</TABLE>
</FORM>



