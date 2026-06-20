# 部署 Orchestrator(5090 @ 10.10.10.2)

当前已部署:**conda env `reelforge`(py3.12)+ systemd 服务 `reelforge`**,监听 `0.0.0.0:8000`,
开机自启、崩溃重启。客户端默认连 `http://10.10.10.2:8000`。

## 已部署的环境
- 代码:`/home/zhangnan/reelforge-orchestrator`(从 Mac rsync)。
- conda env:`/home/zhangnan/.conda/envs/reelforge`(`pip install -r requirements.txt`)。
- 配置:`/home/zhangnan/reelforge-orchestrator/.env`(**含 keys,不入 git**;模板见 `.env.example`)。
- 服务:`/etc/systemd/system/reelforge.service`(本目录有副本)。

## 常用运维
```bash
ssh zhangnan@10.10.10.2
sudo systemctl status reelforge      # 状态
sudo systemctl restart reelforge     # 改 .env / 更新代码后重启
journalctl -u reelforge -f           # 看日志
```

## 更新代码
```bash
# 在 Mac 上
rsync -a --exclude .venv --exclude projects --exclude __pycache__ \
  orchestrator/ zhangnan@10.10.10.2:~/reelforge-orchestrator/
ssh zhangnan@10.10.10.2 'sudo systemctl restart reelforge'
```

## 重新部署(从零)
```bash
ssh zhangnan@10.10.10.2 '/opt/conda/bin/conda create -y -n reelforge python=3.12'
rsync -a orchestrator/ zhangnan@10.10.10.2:~/reelforge-orchestrator/   # 从 Mac
ssh zhangnan@10.10.10.2 '~/.conda/envs/reelforge/bin/pip install -r ~/reelforge-orchestrator/requirements.txt'
# 写 .env(参考 .env.example 填 LITELLM_API_KEY/AGENT_MODEL/VOLCANO_API_KEY)
sudo cp deploy/reelforge.service /etc/systemd/system/ && sudo systemctl enable --now reelforge
```

## 验证
```bash
curl http://10.10.10.2:8000/healthz      # {"ok":true,...}
curl http://10.10.10.2:8000/backends     # local-5090 + local-dgx
```
