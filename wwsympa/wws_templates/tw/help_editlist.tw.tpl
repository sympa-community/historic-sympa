<!-- RCS Identication ; $Revision$ ; $Date$ -->
[FOREACH p IN param]
<A NAME="[p->NAME]">
<B>[p->title]</B> ([p->NAME]):
<DL>
<DD>
[IF p->NAME=add]
  將訂閱者新增ADD 命令)到 Mailing List 的Privilege
[ELSIF p->NAME=anonymous_sender]
  在分發郵件前隱藏發信人郵件地址。
  使用提供的郵件地址來替換原來的地址。
[ELSIF p->NAME=archive]
  讀取郵件存檔和存檔間隔的Privilege
[ELSIF p->NAME=owner]
  所有者管理 Mailing List 的訂閱者。他們可以查看訂閱者，從 Mailing List 中新增刪除郵件地址。
如果您是 Mailing List 的Privilege所有者，您可以選擇 Mailing List 的其它所有者。
   Mailing List 的Privilege所有者可以修改比其它所有者要多的選項。每個 Mailing List 只能有一個Privilege
所有者；他(或她)的郵件地址不能從網頁上進行修改。
[ELSIF p->NAME=editor]
  編輯負責進行消息的監管。如果 Mailing List 要進行監管，發給 Mailing List 的郵件將首先被傳
給編輯，由他們決定是分發還是拒絕它。<BR>
FYI: 定義編輯者不會使 Mailing List 被監管；您必須設置“發送”參數。<BR>
FYI: 如果 Mailing List 被監管，第一個決定分發或拒絕郵件的編輯將替其他的編輯進行決定。
如果沒有任何編輯下決定，郵件將保留在監管隊列中。
[ELSE]
  無可奉告
[ENDIF]

</DL>
[END]
	
