# Azure構成図作成ガイド

## 目的

記事や設計資料に載せるAzure構成図について、技術的な配置関係を正確に示し、資料間で一貫した外観を保つ。

## 基準資料

- 公式アイコン: [Azure architecture icons](https://learn.microsoft.com/en-us/azure/architecture/icons/)
- 確認項目: `azure-checklist.md`
- PNG書き出し: `${CLAUDE_SKILL_DIR}/scripts/export-png.sh`
- テンプレート: `${CLAUDE_SKILL_DIR}/assets/template-azure.drawio`(style文字列はここから写す)

Draw.io Desktopは内蔵のAzureアイコンセット(azure2)を同梱し、CLI書き出しでも描画する。
内蔵セットにあるサービスはダウンロードもSVGの埋め込みも不要で、styleからファイルパスを参照するだけでよい。
内蔵セットにないサービスは、上の公式ページからSVGをダウンロードし、URLエンコード方式で埋め込む
(方式は`principles.md`を参照する)。

## 表現方針

### 情報の優先順位

構成要素、境界、接続方向、データまたは制御の流れを先に配置する。装飾は情報を補助する範囲にとどめる。

階層は、配置、余白、文字サイズ、線の太さを基本に示す。背景色を使用する場合も、色だけに階層や状態の意味を持たせない。

### 色

- Azureサービスとリソースの公式アイコン色は変更しない。
- Azureには、AWS公式ツールキットのグループ色にあたる定義がない。境界枠は白背景と枠線で描き、枠内へ背景色を敷かない。
- 次の色を基本とし、図の目的に応じて意味を定義した色を追加できる。
  - Azure境界(サブスクリプション・仮想ネットワーク・サブネット): `#0078D4`
  - 汎用の枠・主要な矢印: `#404040`
  - 補助線・点線: `#666666`
  - 薄い境界線: `#AAAAAA`
  - 遮断・ブロック: `#CC0000`
  - 背景: `#FFFFFF`
- 既存・新設などの状態を表す目的でAzure公式アイコンの色を変更しない。状態は名称、状態名、線種または凡例で示す。
- 色でサービス区分、状態、経路を補助する場合は、名称、状態名、線種または凡例を併記する。

### 枠と注記

- サービス説明枠(境界ではなく、複数のサービスや説明をまとめる箱)は、白背景、直角、グレーの細線を既定値とする。
- 色付きの角丸枠と同系色の薄い背景を組み合わせたカードを、図全体へ反復する表現は使用しない。
- 注意事項と設計上の前提は、`注記：`などの見出しを付けた通常の本文、または説明と対応する番号付きコールアウトとして配置する。
- 注記の左側に縦線や色帯を置かない。
- 角丸や背景色を使用する場合は、表す対象または意味を図内で一貫させ、単なる統一装飾として全枠へ反復しない。

### アイコン

- 主要なAzureサービスとAzureリソースには、対応する公式アイコンを配置する。
- Draw.io内蔵のアイコンを使う場合、styleは次の形で書く。

```text
image;aspect=fixed;html=1;image=img/lib/azure2/<カテゴリ>/<ファイル名>.svg
```

- 動作を確認済みの主要アイコンのパスは次のとおり。上のstyleの`image=`へ、`img/lib/azure2/`に続けて記載する。パスはDraw.io Desktop 30.4.1の内蔵ファイルの一覧から取り、全件をPNGへ書き出して描画を確認している。

| 分類 | サービスとパス |
|---|---|
| 管理の単位 | Subscription `general/Subscriptions.svg`、Management Groups `general/Management_Groups.svg`、Resource Groups `general/Resource_Groups.svg` |
| コンピュート | App Service `app_services/App_Services.svg`、App Service Plan `app_services/App_Service_Plans.svg`、App Service Environment `app_services/App_Service_Environments.svg`、Function Apps `compute/Function_Apps.svg`、Static Web Apps `preview/Static_Apps.svg`、Virtual Machine `compute/Virtual_Machine.svg`、Virtual Machine Scale Sets `compute/VM_Scale_Sets.svg`、Managed Disks `compute/Disks.svg`、Availability Sets `compute/Availability_Sets.svg`、Azure Virtual Desktop `other/Windows_Virtual_Desktop.svg` |
| コンテナー | Azure Kubernetes Service `containers/Kubernetes_Services.svg`、Container Registry `containers/Container_Registries.svg`、Container Instances `containers/Container_Instances.svg`、Container Apps `other/Worker_Container_App.svg`、Container Apps 環境 `other/Container_App_Environments.svg` |
| ネットワーク | Virtual Network `networking/Virtual_Networks.svg`、Subnet `networking/Subnet.svg`、Network Security Group `networking/Network_Security_Groups.svg`、Application Security Group `security/Application_Security_Groups.svg`、Route Table `networking/Route_Tables.svg`、Network Interface `networking/Network_Interfaces.svg`、Public IP Address `networking/Public_IP_Addresses.svg`、NAT Gateway `networking/NAT.svg`、Load Balancer `networking/Load_Balancers.svg`、Application Gateway `networking/Application_Gateways.svg`、Front Door `networking/Front_Doors.svg`、Traffic Manager `networking/Traffic_Manager_Profiles.svg`、Azure Firewall `networking/Firewalls.svg`、Firewall Policy `networking/Azure_Firewall_Policy.svg`、WAF Policy `networking/Web_Application_Firewall_Policies_WAF.svg`、DDoS Protection Plan `networking/DDoS_Protection_Plans.svg`、Azure Bastion `networking/Bastions.svg`、Private Endpoint `networking/Private_Endpoint.svg`、Private Link Service `networking/Private_Link_Service.svg`、DNS Zone `networking/DNS_Zones.svg`、DNS Private Resolver `networking/DNS_Private_Resolver.svg`、VPN Gateway `networking/Virtual_Network_Gateways.svg`、Local Network Gateway `networking/Local_Network_Gateways.svg`、Connection `networking/Connections.svg`、ExpressRoute Circuit `networking/ExpressRoute_Circuits.svg`、Virtual WAN `networking/Virtual_WANs.svg`、Virtual WAN Hub `networking/Virtual_WAN_Hub.svg`、Network Watcher `networking/Network_Watcher.svg` |
| ストレージ | Storage Account `storage/Storage_Accounts.svg`、Blob コンテナー `general/Storage_Container.svg`、Azure Files `general/Storage_Azure_Files.svg`、Queue Storage `general/Storage_Queue.svg`、Azure NetApp Files `storage/Azure_NetApp_Files.svg`、Recovery Services コンテナー `storage/Recovery_Services_Vaults.svg`、Backup コンテナー `other/Backup_Vault.svg` |
| データベース | SQL Database `databases/SQL_Database.svg`、SQL Server `databases/SQL_Server.svg`、SQL Managed Instance `databases/SQL_Managed_Instance.svg`、Azure Database for MySQL `databases/Azure_Database_MySQL_Server.svg`、Azure Database for PostgreSQL `databases/Azure_Database_PostgreSQL_Server.svg`、Azure Cosmos DB `databases/Azure_Cosmos_DB.svg`、Azure Cache for Redis `databases/Cache_Redis.svg`、Azure Managed Redis `databases/Azure_Managed_Redis.svg` |
| 分析 | Event Hubs `analytics/Event_Hubs.svg`、Stream Analytics `analytics/Stream_Analytics_Jobs.svg`、Azure Synapse Analytics `analytics/Azure_Synapse_Analytics.svg`、Azure Databricks `analytics/Azure_Databricks.svg`、Data Factory `databases/Data_Factory.svg`、Azure Data Explorer `databases/Azure_Data_Explorer_Clusters.svg` |
| 統合 | API Management `integration/API_Management_Services.svg`、Logic Apps `integration/Logic_Apps.svg`、Service Bus `integration/Service_Bus.svg`、Event Grid Topic `integration/Event_Grid_Topics.svg`、App Configuration `integration/App_Configuration.svg`、SignalR Service `web/SignalR.svg` |
| ID | Microsoft Entra ID `identity/Azure_Active_Directory.svg`、Managed Identities `identity/Managed_Identities.svg`、App Registrations `identity/App_Registrations.svg`、Enterprise Applications `identity/Enterprise_Applications.svg`、Microsoft Entra Domain Services `identity/Entra_Domain_Services.svg`、Conditional Access `security/Conditional_Access.svg` |
| セキュリティ | Key Vault `security/Key_Vaults.svg`、Microsoft Defender for Cloud `security/Security_Center.svg`、Microsoft Sentinel `security/Azure_Sentinel.svg` |
| 監視と管理 | Monitor `management_governance/Monitor.svg`、Log Analytics Workspace `analytics/Log_Analytics_Workspaces.svg`、Application Insights `management_governance/Application_Insights.svg`、Azure Policy `management_governance/Policy.svg`、Automation Account `management_governance/Automation_Accounts.svg`、Azure Arc `management_governance/Azure_Arc.svg`、Azure Migrate `migrate/Azure_Migrate.svg` |
| AI | Azure OpenAI `ai_machine_learning/Azure_OpenAI.svg`、Microsoft Foundry `ai_machine_learning/AI_Foundry.svg`、Azure Machine Learning `ai_machine_learning/Azure_Machine_Learning.svg`、Azure AI Search `app_services/Search_Services.svg` |
| 開発 | Azure DevOps `devops/Azure_DevOps.svg` |
| Azure以外の要素 | 利用者 `identity/Users.svg` |

- 内蔵セットのファイル名には旧サービス名のものがある。ファイル名を図中のラベルへ流用せず、ラベルは正式名称で書く。上の表ではMicrosoft Entra ID、Microsoft Sentinel、Microsoft Defender for Cloud、Azure Virtual Desktop、Container Apps、Azure AI Searchが該当する。
- Azure以外の要素のうち、利用者は`identity/Users.svg`、オンプレミスの機器は`onprem-guide.md`の図形で描く。利用者でもオンプレミスの機器でもない要素は、白背景、直角、グレーの細線の箱で描く。
- ファイル名は単数と複数が不規則である(`Virtual_Machine.svg`、`Load_Balancers.svg`)。パスが違うと、アイコンの代わりに壊れた画像の印が描かれる。
- 表にないサービスは、`bash "${CLAUDE_SKILL_DIR}/scripts/find-icon.sh" azure <語>`でパスを検索する。検索で出たパスを使い、PNGでアイコンが描画されたことを確認する。`no match`と出てパスが見つからないときは、公式ページのSVGを埋め込む。表にないパスを使ったサービスと、SVGを埋め込んだサービスは、完了時に伝える。
- Azureサービスを示す箱を文字だけで構成しない。サービス名、公式アイコン、役割を組み合わせる。
- 複数サービスをまとめた箱には、主要なサービスの公式アイコンを並べる。アイコン数は構成要素の識別に必要な範囲とする。
- 装飾目的で構成に存在しないサービスやリソースのアイコンを追加しない。
- Azure公式アイコンは、公式の色、形状、縦横比を維持し、切り抜き、反転、回転を行わない。

### 矢印

- API呼び出し、データ転送、ログ配送は濃いグレーの実線とする。
- 権限、暗号化、依存関係、対象外経路はグレーの破線とする。
- 矢印ラベルには動作を名詞句で記載する。例: `呼び出し`、`ログの配送`、`暗号化`。
- 線の交差を減らし、矢印の始点と終点が要素の中央付近に接続するよう配置する。
- 複数の線種を使用する場合は凡例を置く。
- 濃いグレーの実線はテンプレートに例がないため、次のstyleにする。グレーの破線は、このstyleの`strokeColor`と`fontColor`を`#666666`に替え、`dashed=1;dashPattern=7 5;`を足す。接続点は`drawio.md`に従って書き足す。

```text
fontFamily=IPAPGothic;edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#404040;strokeWidth=1.5;endArrow=block;endFill=1;fontSize=11;fontColor=#404040;labelBackgroundColor=#FFFFFF;
```

### フォント

- 図中の文字はIPA Pゴシックを使用する。Draw.ioのフォント名とXMLの`fontFamily`は`IPAPGothic`とする。
- タイトル、本文、境界名、注記、矢印ラベルを含む全テキスト要素へフォントを明示し、Draw.ioやOSの既定フォントに依存しない。
- 1つの図の中でフォントを混在させない。
- 作図・PNG書き出し環境では、`fc-match IPAPGothic`でIPA Pゴシックが解決されることを事前に確認する。
- IPA Pゴシックがない環境で代替フォントのまま書き出さない。フォントが変わると日本語の字形、文字幅、改行位置が変わる。

フォント名の変更方法と確認コマンドの詳細は`drawio.md`を参照する。

## Azure公式アイコンに基づく作図ルール

- 作成時点で公開されているAzure architecture icons、またはDraw.io内蔵のAzureアイコンセットを使用する。
- 図中のAzure公式アイコンは64×64を標準サイズとし、同じ階層では表示サイズをそろえる。
- 境界の入れ子は、Microsoft Entraテナント、サブスクリプション、仮想ネットワーク(VNet)、サブネットの順とする。構成上存在する範囲だけを記載する。
- リソースグループの枠は、読者の判断に必要な場合だけ記載する。
- App ServiceやStorage Accountなどのリージョンサービスは仮想ネットワークの中に配置しない。閉域アクセスを示す場合は、サブネット内にPrivate Endpointを配置し、対象のリージョンサービスへ線で結ぶ。
- 実在しない仮想ネットワークやサブネットへの配置を示さない。
- Azureサービス名は公式名称で記載する。略称を併記する場合は正式名称を先に記載する。
- 外部サービスは、最も外側に描いたAzure境界(テナントまたはサブスクリプション)の外側に配置する。
- 接続線は直線と直角を基本とする。

## 基本レイアウト

- ページサイズ: 1400×900
- タイトル: 左上、22ポイント
- テナント・サブスクリプション・仮想ネットワーク境界名: 16ポイント
- サービス名・主要説明: 12〜14ポイント
- 注記・矢印ラベル・凡例: 11〜12ポイント
- 主要な処理方向: 左から右
- 入力元: 最も外側に描いたAzure境界の左側
- 監視・鍵管理・分析サービス: 主処理の右側または下側

図の内容が収まらない場合は文字を小さくせず、要素数を減らすかページサイズを見直す。

## 作成手順

1. 本ガイドと`azure-checklist.md`を読む。
2. 図の目的と読者が確認する判断事項を一文で定義する。
3. テナント、サブスクリプション、仮想ネットワーク、サブネットのうち実在する境界を先に配置する。
4. 主要な構成要素を左から右へ並べ、公式アイコンへ置き換える。style文字列は`${CLAUDE_SKILL_DIR}/assets/template-azure.drawio`から写す。アイコンのパスは「アイコン」の表に従う。
5. 閉域アクセスを示す場合は、サブネット内にPrivate Endpointを配置し、対象のリージョンサービスへ線で結ぶ。
6. 実線と破線で接続関係を記載する。
7. 構造と線で表せず、判断を変える前提や対象外があるときだけ、装飾線のない通常テキストまたは番号付きコールアウトで追記する。なければ書かない。
8. draw.io元データを保存し、PNGを書き出す。XMLの書き方、線の接続点、線の経路とラベルは`drawio.md`に従う。
9. `azure-checklist.md`に沿ってPNGを目視確認する。

## 保存と書き出し

書き出しの規則はAWS構成図と共通で、コマンド、環境変数、必要なソフトウェアは`drawio.md`に記載する。

- draw.io元データとPNGは同じ基底名にする。
- draw.io元データを正とし、PNGは掲載用の派生成果物として扱う。
- Draw.io Desktopの`drawio`コマンドをPATHに通して使用する。AppImageの一時パスを通常手順に使用しない。
- PNGは`${CLAUDE_SKILL_DIR}/scripts/export-png.sh`で書き出す。既定では1400×900ピクセルの白背景へ配置し、出力寸法を検証する。
- スクリプトを使用できない場合は、Draw.io Desktopからページ単位、余白0、拡大率100%でPNGを書き出し、1400×900ピクセルであることを確認する。
- PNGを書き出した後、解像度、文字切れ、線、アイコン、重なりを目視確認する。
