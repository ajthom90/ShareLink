FROM alpine:3.22
RUN apk add --no-cache samba samba-common-tools
RUN adduser -D -H -s /sbin/nologin testuser \
 && (echo 'ShareLink-Test-1'; echo 'ShareLink-Test-1') | smbpasswd -s -a testuser \
 && mkdir -p /shares/signed /shares/encrypted && chown -R testuser /shares
COPY smb.conf /etc/samba/smb.conf
EXPOSE 445
CMD ["smbd", "--foreground", "--no-process-group", "--debug-stdout"]
