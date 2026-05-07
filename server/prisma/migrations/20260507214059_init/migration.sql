-- CreateTable
CREATE TABLE "Device" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "hostname" TEXT NOT NULL,
    "platform" TEXT NOT NULL,
    "localIp" TEXT,
    "apiKey" TEXT NOT NULL,
    "online" BOOLEAN NOT NULL DEFAULT false,
    "cpu" REAL NOT NULL DEFAULT 0,
    "ram" REAL NOT NULL DEFAULT 0,
    "vpnActive" BOOLEAN NOT NULL DEFAULT false,
    "proxyPort" INTEGER,
    "rustdeskId" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL
);

-- CreateTable
CREATE TABLE "Session" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "deviceId" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "data" TEXT,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "Session_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "Device" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "SyncJob" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "mutagenId" TEXT,
    "sourceId" TEXT NOT NULL,
    "targetId" TEXT NOT NULL,
    "sourcePath" TEXT NOT NULL,
    "targetPath" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'idle',
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "SyncJob_sourceId_fkey" FOREIGN KEY ("sourceId") REFERENCES "Device" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "SyncJob_targetId_fkey" FOREIGN KEY ("targetId") REFERENCES "Device" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "ProxyConfig" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "deviceId" TEXT NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT false,
    "proxyHost" TEXT,
    "proxyPort" INTEGER,
    "proxyType" TEXT NOT NULL DEFAULT 'socks5',
    CONSTRAINT "ProxyConfig_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "Device" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateIndex
CREATE UNIQUE INDEX "Device_hostname_key" ON "Device"("hostname");

-- CreateIndex
CREATE UNIQUE INDEX "Device_apiKey_key" ON "Device"("apiKey");

-- CreateIndex
CREATE UNIQUE INDEX "ProxyConfig_deviceId_key" ON "ProxyConfig"("deviceId");
