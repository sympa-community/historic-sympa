[IF help_topic]
 [PARSE help_template]

[ELSE]
<BR>
WWSympa vous donne acc�s � votre environnement sur le serveur de listes 
<B>[conf->email]@[conf->host]</B>.
<BR><BR>
Seules les fonctions qui vous sont autoris�es sont affich�es dans
chaque page. Cette interface est donc plus compl�te et facile � utiliser
si vous �tes identifi�s pr�alablement (via le bouton login). Exemple :

<UL>
<LI><TABLE CELLPADDING="2" CELLSPACING="2" BORDER="0">
<TR><TD  NOWRAP>
<TABLE CELLPADDING="2" CELLSPACING="2" BORDER="0">
  <TR ALIGN=center BGCOLOR="--DARK_COLOR--">
  <TD>
  <TABLE WIDTH="100%" BORDER="0" CELLSPACING="0" CELLPADDING="2">
     <TR> 
      <TD NOWRAP BGCOLOR="--LIGHT_COLOR--" ALIGN="center"> 
      <A HREF="[path_cgi]/pref" >
     <FONT SIZE=-1><B>Pr�f�rences</B></FONT></A>
     </TD>
    </TR>
  </TABLE>
  </TD>
</TR>
</TABLE>
</TD><TD> : Pr�f�rences d'usager.  </TD></TR></TABLE>

<LI>
<TABLE CELLPADDING="2" CELLSPACING="2" BORDER="0">
<TR><TD  NOWRAP>
<TABLE CELLPADDING="2" CELLSPACING="2" BORDER="0">
  <TR ALIGN=center BGCOLOR="--DARK_COLOR--">
  <TD>
  <TABLE WIDTH="100%" BORDER="0" CELLSPACING="0" CELLPADDING="2">
     <TR> 
      <TD NOWRAP BGCOLOR="--LIGHT_COLOR--" ALIGN="center"> 
      <A HREF="[path_cgi]/lists" >
     <FONT SIZE=-1><B>liste des listes</B></FONT></A>
     </TD>
    </TR>
  </TABLE>
  </TD>
</TR>
</TABLE>
</TD><TD> : certaines listes sont
acc�ssibles � certaines cat�gories de personnes. Si vous n'�tes pas identfi�,
cette page ne d�livre que la liste des listes publiques. 
</TD></TR></TABLE>

<LI>
<TABLE CELLPADDING="2" CELLSPACING="2" BORDER="0">
<TR><TD  NOWRAP>
<TABLE CELLPADDING="2" CELLSPACING="2" BORDER="0">
  <TR ALIGN=center BGCOLOR="--DARK_COLOR--">
  <TD>
  <TABLE WIDTH="100%" BORDER="0" CELLSPACING="0" CELLPADDING="2">
     <TR> 
      <TD NOWRAP BGCOLOR="--LIGHT_COLOR--" ALIGN="center"> 
      <A HREF="[path_cgi]/which" >
     <FONT SIZE=-1><B>Vos abonnements</B></FONT></A>
     </TD>
    </TR>
  </TABLE>
  </TD>
</TR>
</TABLE>
</TD><TD> : la liste de vos abonnements (et celle des listes que vous administrez).
</TD></TR></TABLE>
<LI>
<TABLE CELLPADDING="2" CELLSPACING="2" BORDER="0">
<TR><TD  NOWRAP>
<TABLE CELLPADDING="2" CELLSPACING="2" BORDER="0">
  <TR ALIGN=center BGCOLOR="--DARK_COLOR--">
  <TD>
  <TABLE WIDTH="100%" BORDER="0" CELLSPACING="0" CELLPADDING="2">
     <TR> 
      <TD NOWRAP BGCOLOR="--LIGHT_COLOR--" ALIGN="center"> 
      <A HREF="[path_cgi]/loginrequest" >
     <FONT SIZE=-1><B>login</B></FONT></A>
     </TD>
    </TR>
  </TABLE></TD>
</TR>
</TABLE>
</TD><TD> / </TD><TD>
<TABLE CELLPADDING="2" CELLSPACING="2" BORDER="0">
  <TR ALIGN=center BGCOLOR="--DARK_COLOR--">
  <TD>
  <TABLE WIDTH="100%" BORDER="0" CELLSPACING="0" CELLPADDING="2">
     <TR> 
      <TD NOWRAP BGCOLOR="--LIGHT_COLOR--" ALIGN="center"> 
      <A HREF="[path_cgi]/logout" >
     <FONT SIZE=-1><B>logout</B></FONT></A>
     </TD>
    </TR>
  </TABLE></TD>
</TR>
</TABLE>
</TD><TD>
 : connexion / d�connexion .
</TD></TR></TABLE>
</UL>

<H2>Login</H2>

Le bouton Login, permet de vous identifier aupr�s du
serveur en renseignant votre adresse email et le mot de passe associ�.
Si vous avez oubli� votre mot de passe, ou si vous n'en avez jamais eu aucun, le bouton
<TABLE CELLPADDING="2" CELLSPACING="2"  BORDER="0">
  <TR ALIGN=center BGCOLOR="--DARK_COLOR--">
  <TD>
  <TABLE WIDTH="100%" BORDER="0" CELLSPACING="0" CELLPADDING="2">
     <TR> 
      <TD NOWRAP BGCOLOR="--LIGHT_COLOR--" ALIGN="center"> 
      <A HREF="[path_cgi]/remindpasswd" >
     <FONT SIZE=-1><B>Recevoir mon mot de passe</B></FONT></A>
     </TD>
    </TR>
  </TABLE></TD>
</TR>
</TABLE>
de la page d'accueil permet de vous en faire allouer (ou r�-allouer) un.

<BR><BR>

Une fois authentifi� un <I>cookie</I> contenant vos information de connection
est envoy� � votre navigateur. Votre adresse apparait en haut � gauche de la page.
La dur�e de vie de ce cookie est param�trable via 
<TABLE CELLPADDING="2" CELLSPACING="2" BORDER="0">
  <TR ALIGN=center BGCOLOR="--DARK_COLOR--">
  <TD>
  <TABLE WIDTH="100%" BORDER="0" CELLSPACING="0" CELLPADDING="2">
     <TR> 
      <TD NOWRAP BGCOLOR="--LIGHT_COLOR--" ALIGN="center"> 
      <A HREF="[path_cgi]/pref" >
     <FONT SIZE=-1><B>Pr�f�rences</B></FONT></A>
     </TD>
    </TR>
  </TABLE></TD>
</TR>
</TABLE>


<BR><BR>
Vous pouvez vous d�connecter (effacer le <I>cookie</I>) � tout moment en utilisant le bouton
<TABLE CELLPADDING="2" CELLSPACING="2" BORDER="0">
  <TR ALIGN=center BGCOLOR="--DARK_COLOR--">
  <TD>
  <TABLE WIDTH="100%" BORDER="0" CELLSPACING="0" CELLPADDING="2">
     <TR> 
      <TD NOWRAP BGCOLOR="--LIGHT_COLOR--" ALIGN="center"> 
      <A HREF="[path_cgi]/logout" >
     <FONT SIZE=-1><B>Logout</B></FONT></A>
     </TD>
    </TR>
  </TABLE></TD>
</TR>
</TABLE>
<BR>
Pour contacter les administrateurs de ce service : <A HREF="mailto:listmaster@[conf->host]">listmaster@[conf->host]</A>

<P>
[ENDIF]

