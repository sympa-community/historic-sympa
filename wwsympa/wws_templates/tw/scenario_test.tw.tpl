<!-- RCS Identication ; $Revision$ ; $Date$ -->


<FORM ACTION="[path_cgi]" METHOD=POST>
    <INPUT TYPE=HIDDEN NAME="action" value="scenario_test">
    <center>
    <TABLE BORDER=0 CELLPADDING=10>
      <TR VALIGN="top">
        <TD COLSPAN=2 NOWRAP>
    	<FONT COLOR="[dark_color]"><CENTER><B>�������ռҶ�</b></CENTER></FONT><BR>
        </TD>
      </TR>
      <TR>
        <TD>�����W</TD>
        <TD>
	  <SELECT NAME="scenario">
	      [FOREACH sc IN scenario]
	        <OPTION VALUE="[sc->NAME]" [sc->selected]>[sc->NAME]
	      [END]
	  </SELECT>
        </TD>
    </TR>
    <TR>
        <TD> Mailing List �W</TD>

        <TD>
	  <SELECT NAME="listname">
	      [FOREACH l IN listname]
	        <OPTION VALUE="[l->NAME]"[l->selected] >[l->NAME]
	      [END]
	  </SELECT>
        </TD>
    </TR>
    <TR>
        <TD>�o�H�H�l��</TD>
        <TD>
          <INPUT TYPE="text" NAME="sender" SIZE="20" value="[sender]">
        </TD>
    </TR>
    <TR>
        <TD>���p�l��</TD>
        <TD>
          <INPUT TYPE="text" NAME="email" SIZE="20" value="[email]">
        </TD>
    </TR>
    <TR>
        <TD>���{�a�}</TD>
        <TD>
          <INPUT TYPE="text" NAME="remote_addr" SIZE="16" value="[remote_addr]">
        </TD>
    </TR>
    <TR>
        <TD>���{�D��</TD>	
        <TD>
          <INPUT TYPE="text" NAME="remote_host" SIZE="16" value="[remote_host]">
        </TD>
    </TR>
    <TR>
        <TD>����Ҧ�</TD>
        <TD>
          <SELECT NAME="auth_method">
              [FOREACH a IN auth_method]
	        <OPTION VALUE="[a->NAME]"[a->selected] >[a->NAME]
	      [END] 
	  </SELECT>
        </TD>
    </TR>
    <TR>

	<TD><INPUT TYPE="submit" NAME="action_scenario_test" VALUE="������Ϊ��W�h"></TD>
        <TD bgcolor="[dark_color]">
          [IF scenario_action]
             <code>[scenario_condition], [scenario_auth_method] -> [scenario_action]</code>
          [ELSE]
          <center>-</center>
          [ENDIF]
        </TD>

      </TR>

    </TABLE>
    </FORM>












