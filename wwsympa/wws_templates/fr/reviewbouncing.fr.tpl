<TABLE width=100% border="0" VALIGN="top">
<TR><TD>
    <FORM ACTION="[path_cgi]" METHOD=POST> 
      <INPUT TYPE="hidden" NAME="previous_action" VALUE="reviewbouncing">
      <INPUT TYPE=hidden NAME=list VALUE=[list]>
      <INPUT TYPE="hidden" NAME="action" VALUE="search">

      <INPUT SIZE=25 NAME=filter VALUE=[filter]>
      <INPUT TYPE="submit" NAME="action_search" VALUE="Recherche">
    </FORM>
</TD>
<TD>
  <FORM METHOD="post" ACTION="[path_cgi]">
    <INPUT TYPE="button" VALUE="Rappel des abonnements" NAME="action_remind" onClick="request_confirm(this.form,'�tes-vous s�r de vouloir envoyer un rappel d\'abonnement � chacun des [total] abonn�s')">
    <INPUT TYPE="hidden" NAME="action" VALUE="remind">
    <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
  </FORM>	
</TD>

</TR></TABLE>
    <FORM NAME="myform" ACTION="[path_cgi]" METHOD=POST>
    <INPUT TYPE="hidden" NAME="list" VALUE="[list]">
    <INPUT TYPE="hidden" NAME="previous_action" VALUE="reviewbouncing">

    <TABLE WIDTH=100% BORDER=0>
    <TR><TD ALIGN="left" NOWRAP>
        <BR>
        <INPUT TYPE="submit" NAME="action_del" VALUE="Supprimer les adresses s�lectionn�es">
        <INPUT TYPE="checkbox" NAME="quiet"> Sans pr�venir

	<INPUT TYPE="hidden" NAME="sortby" VALUE="[tri]">
	<INPUT TYPE="submit" NAME="action_reviewbouncing" VALUE="Taille de page">
	        <SELECT NAME="size">
                  <OPTION VALUE="[size]" SELECTED>[taille]
		  <OPTION VALUE="25">25
		  <OPTION VALUE="50">50
		  <OPTION VALUE="100">100
		   <OPTION VALUE="500">500
		</SELECT>
   </TD>

 <TD ALIGN="right">
        [IF prev_page]
	  <A HREF="[path_cgi]/reviewbouncing/[list]/[prev_page]/[size]"><IMG SRC="/icons/left.gif" BORDER=0 ALT="Page pr�c�dente"></A>
        [ENDIF]
        [IF page]
  	  page [page] / [total_page]
        [ENDIF]
        [IF next_page]
	  <A HREF="[path_cgi]/reviewbouncing/[list]/[next_page]/[size]"><IMG SRC="/icons/right.gif" BORDER=0ALT="Page suivante"></A>
        [ENDIF]
    </TD></TR>
    <TR><TD><INPUT TYPE="submit" NAME="action_resetbounce" VALUE="Annuler les erreurs pour les abonn�s s�lectionn�s">
    </TD></TR>
    </TABLE>

    <TABLE WIDTH="100%" BORDER=1>
      <TR BGCOLOR="--ERROR_COLOR--" NOWRAP>
	<TH><FONT COLOR="--BG_COLOR--">X</FONT></TH>
        <TH><FONT COLOR="--BG_COLOR--">email</FONT></TH>
	<TH><FONT COLOR="--BG_COLOR--">Nombre d'erreurs</FONT></TH>
	<TH><FONT COLOR="--BG_COLOR--">p�riode</FONT></TH>
	<TH NOWRAP><FONT COLOR="--BG_COLOR--">type</FONT></TH>
      </TR>
      
      [FOREACH u IN members]

	[IF dark=1]
	  <TR BGCOLOR="--SHADED_COLOR--">
	[ELSE]
          <TR>
	[ENDIF]

	  <TD>
	    <INPUT TYPE=checkbox name="email" value="[u->escaped_email]">
	  </TD>
	  <TD NOWRAP><FONT SIZE=-1>
	      <A HREF="[path_cgi]/editsubscriber/[list]/[u->escaped_email]/reviewbouncing">[u->email]</A>

	  </FONT></TD>
          <TD ALIGN="center"><FONT SIZE=-1>
  	      [u->bounce_count]
	    </FONT></TD>
	  <TD NOWRAP ALIGN="center"><FONT SIZE=-1>
	    du [u->first_bounce] au [u->last_bounce]
	  </FONT></TD>
	  <TD NOWRAP ALIGN="center"><FONT SIZE=-1>
	    [IF u->bounce_class=2]
	    	succ�s
	    [ELSIF u->bounce_class=4]
		temporaire
	    [ELSIF u->bounce_class=5]
		permanente
	    [ENDIF]
	  </FONT></TD>
        </TR>

        [IF dark=1]
	  [SET dark=0]
	[ELSE]
	  [SET dark=1]
	[ENDIF]

        [END]


      </TABLE>
    <TABLE WIDTH=100% BORDER=0>
    <TR><TD ALIGN="left" NOWRAP>
      [IF is_owner]
        <BR>
        <INPUT TYPE="submit" NAME="action_del" VALUE="Supprimer les adresses s�lectionn�es">
        <INPUT TYPE="checkbox" NAME="quiet"> sans pr�venir
	<INPUT TYPE="submit" NAME="action_resetbounce" VALUE="Annuler les erreurs pour les abonn�s s�lectionn�s">
      [ENDIF]
    </TD><TD ALIGN="right" NOWRAP>
        [IF prev_page]
	  <A HREF="[path_cgi]/reviewbouncing/[list]/[prev_page]/[size]"><IMG SRC="/icons/left.gif" BORDER=0 ALT="Page pr�c�dente"></A>
        [ENDIF]
        [IF page]
  	  page [page] / [total_page]
        [ENDIF]
        [IF next_page]
	  <A HREF="[path_cgi]/reviewbouncing/[list]/[next_page]/[size]"><IMG SRC="/icons/right.gif" BORDER=0ALT="Page suivante"></A>
        [ENDIF]
    </TD></TR>
    <TR><TD><input type=button value="Inverser la Selection" onClick="toggle_selection(document.myform.email)">
    </TD></TR>
    </TABLE>


      </FORM>



