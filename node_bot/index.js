const { Client, GatewayIntentBits, Partials } = require('discord.js');
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: '*' } });
const port = 3000;

// --- Discord Bot Setup ---
// ※ここに直接Tokenを書いてもOKです (例: const TOKEN = 'your-token';)
const TOKEN = process.env.DISCORD_TOKEN || 'YOUR_BOT_TOKEN_HERE';

const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent
  ],
  partials: [Partials.Channel]
});

function broadcastLog(message) {
  const timestamp = new Date().toLocaleTimeString();
  const logMessage = `[${timestamp}] [Node] ${message}`;
  console.log(logMessage);
  io.emit('log', logMessage);
}

client.on('ready', () => {
  broadcastLog(`Logged in as ${client.user.tag}!`);
});

client.on('messageCreate', message => {
  if (message.author.bot) return;
  broadcastLog(`Message from ${message.author.tag}: ${message.content}`);
  if (message.content === 'ping') {
    message.reply('pong').then(() => broadcastLog('Replied with pong'));
  }
});

// Socket.io Events
io.on('connection', (socket) => {
  socket.emit('log', `[System] Connected to Node Bot Server`);
  socket.on('command', (cmd) => {
    if (cmd === 'stop') {
      broadcastLog('Stopping bot via remote command...');
      setTimeout(() => process.exit(0), 500);
    }
  });
});

server.listen(port, '0.0.0.0', () => {
  broadcastLog(`Server listening at http://0.0.0.0:${port}`);
});

if (TOKEN === 'YOUR_BOT_TOKEN_HERE') {
  broadcastLog('Error: TOKEN is not set (YOUR_BOT_TOKEN_HERE)');
} else {
  client.login(TOKEN).catch(err => broadcastLog(`Login Failed: ${err.message}`));
}
