<!-- RCS Identication ; $Revision$ ; $Date$ -->

[IF action=search_list]
  ��� [occurrence] �Ӭ��� Mailing List <BR><BR>
[ELSIF action=search_user]
  <B>[email]</B> �w�q�\�U�C Mailing List 
[ENDIF]

<TABLE BORDER="0" WIDTH="100%">
   [FOREACH l IN which]
     <TR>
      [IF l->admin]
       <TD BGCOLOR="[dark_color]">
          <TABLE BORDER="0" WIDTH="100%" CELLSPACING="0" CELLPADDING="1">
           <TR><TD BGCOLOR="[light_color]" ALIGN="center" VALIGN="top">
             <FONT COLOR="[selected_color]" SIZE="-1">
              <A HREF="[path_cgi]/admin/[l->NAME]" ><b>�޲z</b></A>
         </FONT>
       </TD>
     </TR>
 </TABLE>
</TD>
     [ELSE]
       <TD>&nbsp;</TD>
     [ENDIF] 
     <TD WIDTH="100%" ROWSPAN="2">
     <A HREF="[path_cgi]/info/[l->NAME]" ><B>[l->NAME]@[l->host]</B></A>
     <BR>
     [l->subject]
     </TD></TR>
     <TR><TD>&nbsp;</TD></TR>
     [END]
</TABLE>

<BR>

[IF action=which]
[IF ! which]
&nbsp;&nbsp;<FONT COLOR="[dark_color]">�S���Ӧ� <B>[user->email]</B> ���q�\!</FONT>
<BR>
[ENDIF]

[IF unique <> 1]
<TABLE>
&nbsp;&nbsp;<FONT COLOR="[dark_color]">�H���U�� Email �d�ݱz���q�\���p</FONT><BR>
<BR><BR>

 <TR> 
    <FORM METHOD=POST ACTION="[path_cgi]">
     
[FOREACH email IN alt_emails]
   <INPUT NAME="email"  TYPE=hidden VALUE="[email->NAME]">
   &nbsp;&nbsp;<A HREF="[path_cgi]/change_identity/[email->NAME]/which">[email->NAME]</A> 
    <BR>
    [END]  
    </FORM>
  </TR>
</TABLE>

<BR> 

<TABLE>
<TR>
&nbsp;&nbsp;<FONT COLOR="[dark_color]">�H Email  <B>[user->email]</B> �Τ@�q�\</FONT><BR> 
&nbsp;&nbsp;<FONT COLOR="[dark_color]">�]�N�O��, �H��@�� Email �Τ@�޲z�z�� Sympa �q�\�γ]�w</FONT>

<TR>
<TD>
    <FORM ACTION="[path_cgi]" METHOD=POST>
  
&nbsp;&nbsp;<INPUT TYPE="submit" NAME="action_unify_email" VALUE="�T�w"></FONT>
    </FORM>
</TD>
</TR>
<BR>

</TABLE>
[ENDIF]
[ENDIF]
