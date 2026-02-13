import discord
from discord import app_commands
from discord.ui import View, Button
from discord import AllowedMentions
import asyncio
from datetime import datetime
import aiohttp

TOKEN = "YOUR_BOT_TOKEN_HERE"
WEBHOOK_URL = "YOUR_WEBHOOK_URL_HERE"

class MyClient(discord.Client):
    def __init__(self):
        super().__init__(intents=discord.Intents.default())
        self.tree = app_commands.CommandTree(self)

    async def on_ready(self):
        print(f"✅ ログイン完了: {self.user}")
        await self.tree.sync()
        print("🌐 スラッシュコマンド登録完了")

    # Webhookでログを送信するメソッド
    async def send_webhook_log(self, title, description, interaction: discord.Interaction, color_code=0x3498db):
        async with aiohttp.ClientSession() as session:
            webhook = discord.Webhook.from_url(WEBHOOK_URL, session=session)
            
            # サーバー情報の取得
            guild_name = interaction.guild.name if interaction.guild else "DM"
            guild_id = interaction.guild.id if interaction.guild else "N/A"
            
            embed = discord.Embed(
                title=title,
                description=description,
                color=color_code,
                timestamp=datetime.now()
            )
            # フィールドにサーバー情報を追加
            embed.add_field(name="サーバー名", value=guild_name, inline=True)
            embed.add_field(name="サーバーID", value=f"`{guild_id}`", inline=True)
            embed.add_field(name="チャンネル", value=interaction.channel.mention, inline=False)
            
            embed.set_footer(text=f"実行者: {interaction.user.name} ({interaction.user.id})", icon_url=interaction.user.display_avatar.url)
            
            await webhook.send(
                embed=embed,
                username="Bot Action Log"
            )

client = MyClient()

class SpamView(View):
    def __init__(self, allow_everyone: bool, interval: float):
        super().__init__(timeout=None)
        self.allow_everyone = allow_everyone
        self.interval = interval
        self.add_item(SpamButton(allow_everyone, interval))

class SpamButton(Button):
    def __init__(self, allow_everyone: bool, interval: float):
        super().__init__(label="SPAM開始", style=discord.ButtonStyle.green)
        self.allow_everyone = allow_everyone
        self.interval = interval

    async def callback(self, interaction: discord.Interaction):
        await interaction.response.defer()
        
        # ログ送信
        await client.send_webhook_log(
            "🚨 スパムボタン実行(強化版)", 
            f"間隔: {self.interval}秒 でSPAMが開始されました。\nモード: {'⚡ 並列高速実行' if self.interval <= 0 else '⏳ 順次実行'}", 
            interaction,
            0xe74c3c
        )
        
        allowed = AllowedMentions(everyone=self.allow_everyone, users=True, roles=True)
        content = f"# @everyone\n# Raid by MKND Team!\n# Join Now!\n# そんなゴミ鯖で遊んでないでMKNDに今すぐ参加しろ！\n## [VDRS](https://discord.gg/PVtfv5DNEY)\n# [頑張って消してねww](https://imgur.com/a/mSLBomC)"

        try:
            if self.interval <= 0:
                # 【強化】間隔0秒なら並列処理で一気に送信（GPUではなく非同期IOパワーを使用）
                tasks = []
                for _ in range(10): # 回数を5回から10回に強化
                    tasks.append(interaction.followup.send(
                        content, 
                        allowed_mentions=allowed, 
                        ephemeral=False
                    ))
                # エラーを無視して実行（return_exceptions=True）
                results = await asyncio.gather(*tasks, return_exceptions=True)
                
                success_count = sum(1 for r in results if not isinstance(r, Exception))
                print(f"⚡ 高速送信完了: {success_count}/10 成功")
            
            else:
                # 従来の間隔ありモード
                for i in range(5):
                    await interaction.followup.send(
                        content, 
                        allowed_mentions=allowed, 
                        ephemeral=False
                    )
                    if i < 4:
                        await asyncio.sleep(self.interval)

        except Exception as e:
            print(f"❌ エラー発生: {e}")
            await interaction.followup.send(f"⚠️ エラーが発生しました: {e}", ephemeral=True)

@client.tree.command(name="send", description="指定したメッセージを一度だけ送信します")
async def sayonce(interaction: discord.Interaction, message: str, allow_everyone: bool = True):
    await interaction.response.send_message(f"✅ メッセージを送信しました", ephemeral=True)
    
    await client.send_webhook_log(
        "📝 メッセージ送信(/send)", 
        f"内容: {message}", 
        interaction
    )

    allowed = AllowedMentions(everyone=allow_everyone, users=True, roles=True)
    await interaction.followup.send(message, allowed_mentions=allowed, ephemeral=False)

@client.tree.command(name="spam", description="ボタンを押すとSPAMを開始します")
async def spamtest(interaction: discord.Interaction, allow_everyone: bool = True, interval: float = 0.0):
    view = SpamView(allow_everyone, interval)
    everyone_status = "許可" if allow_everyone else "禁止"
    
    await client.send_webhook_log(
        "🛠️ スパムパネル設置(/spam)", 
        f"設定: @everyone {everyone_status} | 間隔 {interval}秒", 
        interaction,
        0xe67e22
    )

    await interaction.response.send_message(
        f"ボタンを押すとSPAMを開始します\n設定: @everyone {everyone_status} | 間隔 {interval}秒",
        view=view,
        ephemeral=True
    )

client.run(TOKEN)