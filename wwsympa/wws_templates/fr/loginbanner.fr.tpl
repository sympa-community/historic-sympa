<BR>
[IF password_sent]
  Votre mot de passe vous a �t� envoy� � l'adresse [init_email].<BR>
  Relevez votre bo�te aux lettres  pour renseigner votre mot de passe ci-dessous. 
  <BR><BR>
[ENDIF]

[IF action=loginrequest]
Identifiez-vous pour : <UL>
  <LI>effectuer une op�ration privil�gi�e
  <LI>acc�der � votre environnement personnel
</UL>

[ELSE]
 La plupart des services n�cessitent votre adresse email. Certaines listes sont
cach�es aux personnes non identif�es.<BR>
Pour b�n�ficier de l'acc�s int�gral � ce serveur de listes, vous
devez probablement vous identifier pr�alablement.<BR>
[ENDIF]

    <FORM ACTION="[path_cgi]" METHOD=POST> 
        <INPUT TYPE="hidden" NAME="previous_action" VALUE="[previous_action]">
        <INPUT TYPE="hidden" NAME="previous_list" VALUE="[previous_list]">
	<INPUT TYPE="hidden" NAME="referer" VALUE="[referer]">
	<INPUT TYPE="hidden" NAME="action" VALUE="login">
	<INPUT TYPE="hidden" NAME="nomenu" VALUE="[nomenu]">
	

        <TABLE BORDER=0 width=100% CELLSPACING=0 CELLPADDING=0>
         <TR BGCOLOR="--LIGHT_COLOR--">
          <TD NOWRAP align=center>
     	      <INPUT TYPE=hidden NAME=list VALUE="[list]">
     	      <FONT SIZE=-1 COLOR="--SELECTED_COLOR--"><b>adresse �lectronique <INPUT TYPE=text NAME=email SIZE=20 VALUE="[init_email]">
      	      mot de passe : </b>
              <INPUT TYPE=password NAME=passwd SIZE=8>&nbsp;&nbsp;
              <INPUT TYPE="submit" NAME="action_login" VALUE="Login" SELECTED>
   	    </TD>
     	  </TR>
       </TABLE>
 </FORM> 

<CENTER>

<TABLE border=0><TR>
<TD>
<I>Si vous n'avez jamais eu de mot de passe sur ce serveur ou si vous l'avez oubli� :</I>
</TD><TD>
<TABLE CELLPADDING="2" CELLSPACING="2" WIDTH="100%" BORDER="0">
  <TR ALIGN=center BGCOLOR="--DARK_COLOR--">
  <TD>
  <TABLE WIDTH="100%" BORDER="0" CELLSPACING="0" CELLPADDING="2">
     <TR> 
      <TD NOWRAP BGCOLOR="--LIGHT_COLOR--" ALIGN="center"> 
	<A HREF="[path_cgi]/nomenu/remindpasswd/referer/[referer]"
         onClick="window.open('','wws_login','toolbar=no,location=no,directories=no,status=no,menubar=no,scrollbars=yes,resizable=yes,copyhistory=no,width=450,height=300')" TARGET="wws_login" >

     <FONT SIZE=-1><B>Envoyez moi mon mot de passe</B></FONT></A>
     </TD>
    </TR>
  </TABLE>
</TR>
</TABLE>
</TD></TR></TABLE>
</CENTER>




