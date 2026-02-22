# 虚拟机配置 GitHub SSH 免密登录

> 目标：在虚拟机（CentOS / Linux）中配置 SSH 密钥，实现免密推送代码到 GitHub。
>
> 前提：虚拟机已能正常联网。

---

## 一、生成 SSH 密钥

### 1.1 清理旧密钥（可选）

如果之前已经生成过 SSH 密钥，想重新生成，先删除旧的：

```bash
cd ~
rm -rf .ssh
```

> ⚠️ 注意：这会删除所有已有的 SSH 密钥，如果有其他用途的密钥请谨慎操作。

### 1.2 生成新的 SSH 密钥对

```bash
ssh-keygen -t rsa -C "test@qq.com"
```

执行后会出现以下提示，**全部按回车即可**（使用默认路径，不设置密码）：

```
Generating public/private rsa key pair.
Enter file in which to save the key (/root/.ssh/id_rsa):    ← 直接回车
Enter passphrase (empty for no passphrase):                  ← 直接回车
Enter same passphrase again:                                 ← 直接回车
```

生成完成后会看到类似输出：

```
Your identification has been saved in /root/.ssh/id_rsa.
Your public key has been saved in /root/.ssh/id_rsa.pub.
```

### 1.3 查看公钥内容

```bash
cat ~/.ssh/id_rsa.pub
```

输出类似：

```
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ... test@qq.com
```

**复制整段公钥内容**，后面要粘贴到 GitHub。

> 💡 如果终端不方便复制，可以用 `Xshell`、`MobaXterm` 等工具连接虚拟机操作，方便选中复制。

---

## 二、在 GitHub 上添加 SSH 公钥

### 2.1 打开 GitHub SSH 设置页面

1. 登录 [GitHub](https://github.com)
2. 点击右上角头像 → **Settings**
3. 左侧菜单选择 **SSH and GPG keys**
4. 点击 **New SSH key**

> 或直接访问：https://github.com/settings/ssh/new

### 2.2 填写公钥信息

| 字段    | 填写内容                       |
| ------- | ------------------------------ |
| Title   | 自定义名称，如 `saas-dev-vm`   |
| Key type | 保持默认 `Authentication Key` |
| Key     | 粘贴上一步复制的公钥内容       |

填写完成后点击 **Add SSH key**，可能需要输入 GitHub 密码确认。

---

## 三、验证 SSH 连接

回到虚拟机终端，执行：

```bash
ssh -T git@github.com
```

首次连接会提示：

```
The authenticity of host 'github.com (20.205.243.166)' can't be established.
ED25519 key fingerprint is SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU.
Are you sure you want to continue connecting (yes/no)?
```

**输入 `yes` 回车**，看到以下信息说明配置成功：

```
Hi <你的用户名>! You've successfully authenticated, but GitHub does not provide shell access.
```

---

## 四、配置 Git 用户信息

如果虚拟机上还没有配置 Git 的用户名和邮箱，需要设置：

```bash
git config --global user.name "你的GitHub用户名"
git config --global user.email "2544528304@qq.com"
```

验证配置：

```bash
git config --global --list
```

---

## 五、使用 SSH 方式克隆/推送仓库

### 5.1 克隆仓库（使用 SSH 地址）

在 GitHub 仓库页面，点击 **Code** → 选择 **SSH** → 复制地址：

```bash
git clone git@github.com:你的用户名/仓库名.git
```

### 5.2 测试推送

```bash
git add .
git commit -m "test: 测试 SSH 免密推送"
git push origin main
```

如果推送成功且没有要求输入密码，说明 SSH 免密登录配置完成！

---

## 总结

| 步骤 | 操作 |
| ---- | ---- |
| 1    | 虚拟机生成 SSH 密钥：`ssh-keygen -t rsa -C "邮箱"` |
| 2    | 复制公钥：`cat ~/.ssh/id_rsa.pub` |
| 3    | GitHub → Settings → SSH keys → 添加公钥 |
| 4    | 验证连接：`ssh -T git@github.com` |
| 5    | 使用 SSH 地址克隆/推送仓库 |
