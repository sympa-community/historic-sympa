<!-- RCS Identication ; $Revision$ ; $Date$ -->

[FOREACH error IN errors]

[IF error->msg=unknown_action]
[error->action] : 未知操作

[ELSIF error->msg=unknown_list]
[error->list] : 未知 Mailing List 

[ELSIF error->msg=already_login]
您已經以 [error->email]  Login 

[ELSIF error->msg=no_email]
請輸入您的電子郵件地址

[ELSIF error->msg=incorrect_email]
地址“[error->email]”是錯誤的

[ELSIF error->msg=incorrect_listname]
“[error->listname]”: 錯誤的 Mailing List 名

[ELSIF error->msg=no_passwd]
請輸入您的密碼

[ELSIF error->msg=user_not_found]
“[error->email]”: 未知用戶

[ELSIF error->msg=user_not_found]
“[error->email]”不是訂閱者

[ELSIF error->msg=passwd_not_found]
用戶“[error->email]”沒有密碼

[ELSIF error->msg=incorrect_passwd]
輸入的密碼不正確

[ELSIF error->msg=uncomplete_passwd]
輸入的密碼不完整

[ELSIF error->msg=no_user]
您需要先 Login 

[ELSIF error->msg=may_not]
[error->action]: 您不被允許進行這個操作
[IF ! user->email]
<BR>您需要先 Login 
[ENDIF]

[ELSIF error->msg=no_subscriber]
 Mailing List 沒有訂閱者

[ELSIF error->msg=no_bounce]
 Mailing List 沒有被退信的訂閱者

[ELSIF error->msg=no_page]
沒有頁 [error->page]

[ELSIF error->msg=no_filter]
缺少過濾

[ELSIF error->msg=file_not_editable]
[error->file]: 文件不可編輯

[ELSIF error->msg=already_subscriber]
您已經訂閱了 Mailing List  [error->list]

[ELSIF error->msg=user_already_subscriber]
[error->email] 已經訂閱了 Mailing List  [error->list] 

[ELSIF error->msg=failed_add]
新增使用者 [error->user] 失敗

[ELSIF error->msg=failed]
[error->action]: 操作失敗

[ELSIF error->msg=not_subscriber]
[IF error->email]
  並非訂閱者: [error->email]
[ELSE]
您不是 Mailing List  [error->list] 的訂閱者
[ENDIF]

[ELSIF error->msg=diff_passwd]
兩個密碼不一致

[ELSIF error->msg=missing_arg]
缺少參數 [error->argument]

[ELSIF error->msg=no_bounce]
用戶 [error->email] 沒有退信

[ELSIF error->msg=update_privilege_bypassed]
您在沒有權限的情況下修改了一個參數: [error->pname]

[ELSIF error->msg=config_changed]
設定文件已經被 [error->email] 修改。無法應用您的修改

[ELSIF error->msg=syntax_errors]
下列參數語法錯誤: [error->params]

[ELSIF error->msg=no_such_document]
[error->path]: 沒有此文件或目錄

[ELSIF error->msg=no_such_file]
[error->path] : 沒有此文件

[ELSIF error->msg=empty_document] 
無法讀取 [error->path] : 空的文檔

[ELSIF error->msg=no_description] 
沒有指定描述

[ELSIF error->msg=no_content]
錯誤: 您提供的內容是空的

[ELSIF error->msg=no_name]
沒有指定名字

[ELSIF error->msg=incorrect_name]
[error->name]: 不正確的名字

[ELSIF error->msg = index_html]
您沒有被授權上傳一個 INDEX.HTML 到 [error->dir] 

[ELSIF error->msg=synchro_failed]
磁盤數據已經改變。無法應用您的修改

[ELSIF error->msg=cannot_overwrite] 
無法覆蓋文件 [error->path] : [error->reason]

[ELSIF error->msg=cannot_upload] 
無法上傳文件 [error->path] : [error->reason]

[ELSIF error->msg=cannot_create_dir] 
無法建立目錄 [error->path] : [error->reason]

[ELSIF error->msg=full_directory]
失敗: [error->directory] 不為空

[ELSIF error->msg=init_passwd]
您並未選取密碼, 請要求一份原先密碼的提醒
 
[ELSIF error->msg=change_email_failed]
無法更改 [error->list] 的 Email 

[ELSIF error->msg=change_email_failed_because_subscribe_not_allowed]
無法更新論壇 '[error->list]' 的訂閱位址,
因為已禁止以新的位址訂閱.

[ELSIF error->msg=change_email_failed_because_unsubscribe_not_allowed]
無法更新論壇 '[error->list]' 的訂閱位址,
因為已禁止取消訂閱.

[ELSE]
[error->msg]
[ENDIF]

<BR>
[END]
