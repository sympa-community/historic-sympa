<!-- RCS Identication ; $Revision$ ; $Date$ -->

[IF status = done]
<b>操作成功</b>。
郵件將盡快被刪除。這個任務可能在幾分鐘內完成，不要忘記重新載入涉及到的頁面。
[ELSIF status = no_msgid]
<b>無法找到要刪除的郵件，也許收到此郵件時沒有“Message-Id:”。請用完整的 URL
或涉及到的郵件向 Mailing List 管理者詢問。</b>
[ELSIF status = not_found]
<b>無法找到要刪除的郵件</b>
[ELSE]
<b>在刪除此郵件時發生錯誤，請用完整的 URL 或涉及到的郵件向 Mailing List 管理者詢問。</b>
[ENDIF]
