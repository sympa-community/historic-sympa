[FOREACH notice IN notices]

[IF notice_msg=sent_to_owner]
您的請求已經被轉發給 Mailing List 所有者

[ELSIF notice_msg=performed]
[notice->action]: 操作成功

[ELSIF notice_msg=list_config_updated]
設定文件已經被更新

[ELSIF notice_msg=upload_success] 
成功上傳文件 [notice->path] !

[ELSIF notice_msg=save_success] 
文件 [notice->path] 已保存

[ELSE]
[notice->msg]

[ENDIF]

<BR>
[END]




