# AWS構成図作成ガイド

## 目的

記事や設計資料に載せるAWS構成図について、技術的な配置関係を正確に示し、資料間で一貫した外観を保つ。

## 基準資料

- 公式アイコン: [AWS Architecture Icons](https://aws.amazon.com/jp/architecture/icons/)
- 確認項目: `aws-checklist.md`
- PNG書き出し: `${CLAUDE_SKILL_DIR}/scripts/export-png.sh`
- テンプレート: `${CLAUDE_SKILL_DIR}/assets/template-aws.drawio`(style文字列はここから写す)

AWS公式アイコンのSVGは、上のページからツールキットをダウンロードして使う。容量が大きいため
本リポジトリには同梱しない。draw.ioでは内蔵の `mxgraph.aws4.*` 図形を使えばSVGの埋め込みは不要。

## 表現方針

### 情報の優先順位

構成要素、境界、接続方向、データまたは制御の流れを先に配置する。装飾は情報を補助する範囲にとどめる。

階層は、配置、余白、文字サイズ、線の太さを基本に示す。背景色を使用する場合も、色だけに階層や状態の意味を持たせない。

### 色

- AWSサービスとリソースの公式アイコン色は変更しない。
- AWS公式ツールキットのグループ色は使用できる。独自の色へ変更しない。
- Draw.ioでは、公式の`shape`、`resIcon`、`grIcon`を選んだだけで色も正しいとは判断しない。要素ごとに`fillColor`、`strokeColor`、`fontColor`をAWS公式ツールキットと照合する。
- AWS公式アイコンはサービスカテゴリごとの公式色、AWS公式グループはグループごとの公式色を維持する。例として、AWS Cloudは`#232F3E`、VPCは`#8C4FFF`を使用する。
- AWS公式グループの線は、AWSアカウントが`#E7157B`、リージョンが`#00A4A6`の点線、Availability Zoneが`#00A4A6`の破線、パブリックサブネットが`#7AA116`、プライベートサブネットが`#00A4A6`で、いずれも塗りなしである(AWS公式のPowerPointツールキット2026年7月31日版)。枠のstyleはテンプレートから写す。テンプレートのサブネットはプライベート用で、パブリックサブネットは`strokeColor`を`#7AA116`に替える(枠のアイコンは同じ)。AWSアカウントの枠はテンプレートにないため、VPCの枠のstyleの`grIcon`を`mxgraph.aws4.group_account`に、`strokeColor`と`fontColor`を`#E7157B`に、`fontSize`を16に替える。
- 既存・新設などの状態を表す目的でAWS公式アイコンやAWS公式グループの色を変更しない。状態は名称、状態名、線種または凡例で示す。
- 色でサービス区分、状態、経路を補助する場合は、名称、状態名、線種または凡例を併記する。
- 次の色を基本とし、図の目的に応じてAWS公式色または意味を定義した色を追加できる。
  - 見出し・AWS Cloud境界: `#232F3E`
  - 本文・主要な矢印: `#414D5C`
  - 補助線・点線: `#687078`
  - 判断事項に関わる経路を強調する線: `#147EBA`
  - 薄い境界線: `#AAB7B8`
  - 背景: `#FFFFFF`

### 枠と注記

- サービス説明枠(境界ではなく、複数のサービスや説明をまとめる箱)は、白背景、直角、グレーの細線を既定値とする。
- 色付きの角丸枠と同系色の薄い背景を組み合わせたカードを、図全体へ反復する表現は使用しない。
- 注意事項と設計上の前提は、`注記：`などの見出しを付けた通常の本文、または説明と対応する番号付きコールアウトとして配置する。
- 注記の左側に縦線や色帯を置かない。
- 角丸や背景色を使用する場合は、表す対象または意味を図内で一貫させ、単なる統一装飾として全枠へ反復しない。

### アイコン

- 主要なAWSサービスとAWSリソースには、対応する公式アイコンを配置する。
- AWSサービスを示す箱を文字だけで構成しない。サービス名、公式アイコン、役割を組み合わせる。
- 複数サービスをまとめた箱には、主要なサービスの公式アイコンを並べる。アイコン数は構成要素の識別に必要な範囲とする。
- 公式のリソースアイコンがある場合は、サービスアイコンだけでなくリソースアイコンも使用できる。
- 装飾目的で構成に存在しないサービスやリソースのアイコンを追加しない。
- AWS公式アイコンは、公式ツールキットの色、形状、縦横比を維持し、切り抜き、反転、回転を行わない。

### 矢印

- API呼び出し、データ転送、ログ配送は濃いグレーの実線とする。
- 権限、暗号化、依存関係、設定の関連付け、対象外経路はグレーの破線とする。
- 矢印ラベルには動作を名詞句で記載する。例: `呼び出し`、`ログの配送`、`暗号化`。
- 線の交差を減らし、矢印の始点と終点が要素の中央付近に接続するよう配置する。
- 複数の線種を使用する場合は凡例を置く。
- 濃いグレーの実線はテンプレートに例がないため、次のstyleにする。グレーの破線は、このstyleの`strokeColor`と`fontColor`を`#687078`に、`strokeWidth`を2に替え、`dashed=1;dashPattern=7 5;`を足す(テンプレートの`phase0`と同じ線)。判断事項に関わる経路を強調する線は、テンプレートの`phase1to3-a`のstyleを写す。接続点は`drawio.md`に従って書き足す。

```text
fontFamily=IPAPGothic;edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#414D5C;strokeWidth=1.5;endArrow=block;endFill=1;fontSize=11;fontColor=#414D5C;labelBackgroundColor=#FFFFFF;
```

### フォント

- 図中の文字はIPA Pゴシックを使用する。Draw.ioのフォント名とXMLの`fontFamily`は`IPAPGothic`とする。
- タイトル、本文、境界名、注記、矢印ラベルを含む全テキスト要素へフォントを明示し、Draw.ioやOSの既定フォントに依存しない。
- 1つの図の中でフォントを混在させない。
- 作図・PNG書き出し環境では、`fc-match IPAPGothic`でIPA Pゴシックが解決されることを事前に確認する。
- IPA Pゴシックがない環境で代替フォントのまま書き出さない。フォントが変わると日本語の字形、文字幅、改行位置が変わる。

AWS公式の2026年4月版Microsoft PowerPointツールキットは、テーマで欧文にArial、日本語にMS Pゴシックを指定している。AWSアーキテクチャアイコンの利用条件として特定フォントが必須とされているわけではないため、ここでは日本語の字形とLinuxでの再現性を優先してIPA Pゴシックへ統一する。

## AWS公式ツールキットに基づく作図ルール

- 作成時点で公開されているAWS Architecture Iconsを使用する。
- AWS公式ツールキットのアイコン、グループ、矢印を使用する。
- 図中のAWS公式アイコンは60×60を標準サイズとし、同じ階層では表示サイズをそろえる。
- AWS Cloud、AWSアカウント、リージョン、Availability Zone、VPC、サブネットの境界は、構成上存在する範囲を記載する。ただしAWSアカウントの境界は、1つのアカウントだけを描く図では省略できる。複数のアカウントを描く図と、アカウントの違いが判断事項に関わる図では記載する。
- リージョンサービスに対して、実在しないVPC、Availability Zone、サブネットへの配置を示さない。
- AWSサービス名は公式名称で記載する。略称を併記する場合は正式名称を先に記載する。
- 外部サービスはAWS Cloud境界の外側に配置する。
- 接続線は直線と直角を基本とする。

## サービスごとの描き方

- グローバルサービス(CloudFront、Route 53、IAM)は、AWS Cloud境界の中、リージョン境界の外に置く。アカウント境界を描く図では、アカウント境界の中に置く。リージョンサービス(S3、DynamoDB、CloudWatch等)はリージョン境界の中、VPCの外に置く。
- AWS WAFは通信経路に挟まない。CloudFrontに付けるものはリージョン境界の外、ALB等に付けるものはリージョン境界の中かつVPCの外に置き、関連付け先へ破線を引く。
- CloudFrontに付けるACM証明書はus-east-1で発行する。CloudFrontに付けるWAFと同じくリージョン境界の外に置き、ラベルに発行リージョンを書く。
- ALBやNLBは、AZごとに重ねて描かず、ロードバランサー1つにつき1つ描き、VPC境界の中、AZ境界の外に置く。配置先のサブネットはラベルに書く。ロードバランサーは複数AZのサブネットにまたがる1つのリソースである。
- 設定として関連付けるだけの関係の矢印は、WAFやACMから関連付け先へ向ける。

## アイコン名

draw.io内蔵の`mxgraph.aws4`図形の名前と塗り色を示す。名前はDraw.io Desktop 30.4.1のパレット定義から取り、色はAWS Architecture Iconsの2026年7月31日版と照合した。全件をPNGへ書き出し、絵が出ることを確認している。

- 名前は、サービス名を小文字と下線にしただけでは当たらないものがある。CloudWatchは`cloudwatch_2`、OpenSearch Serviceは`elasticsearch_service`、IAM Identity Centerは`single_sign_on`である。
- 名前が違うと絵が出ず、塗り色の四角だけになる。表にないサービスは、次の順で名前を決める。
  1. `bash "${CLAUDE_SKILL_DIR}/scripts/find-icon.sh" aws <語>`で検索する。
  2. 出力が`resIcon=`で始まる行はサービスアイコン、`shape=`で始まる行はリソースアイコンのstyleに使用する。色は、出力のカテゴリと同じ行の値を使用する。
  3. PNGで絵が出たことを確認する。
  4. `no match`と出たときは、公式アイコンのSVGを埋め込む(方式は`drawio.md`)。
  5. 表にない名前を使用したサービス、SVGを埋め込んだサービス、同じ名前が複数のカテゴリで出て選んだカテゴリを、完了時に伝える。
- 色は表の値を使用する。表にないサービスは、同じカテゴリの行の色を使用する。表にないカテゴリの色は、Media Services、Blockchain、Quantum Technologiesが`#ED7100`、Gamesが`#8C4FFF`、Satellite、Customer Enablementが`#C925D1`、Generalが`#232F3D`である。
- Draw.ioのパレットには、公式パッケージと違うカテゴリの色で載っている図形がある(Elastic Load Balancing、API Gateway、Redshift、Organizations等)。パレットの色ではなく表の色を使用する。

### サービスアイコン

テンプレートのサービスアイコンのstyleを写し、`fillColor`と`resIcon=mxgraph.aws4.<名前>`を差し替える。styleにある`shape=mxgraph.aws4.resourceIcon`はサービスアイコンを描く図形の名前で、下の「リソースアイコン」とは別である。

| カテゴリ | `fillColor` | サービスと名前 |
|---|---|---|
| Compute | `#ED7100` | EC2 `ec2`、EC2 Auto Scaling `auto_scaling2`、Lambda `lambda`、Elastic Beanstalk `elastic_beanstalk`、Batch `batch`、App Runner `app_runner` |
| Containers | `#ED7100` | ECS `ecs`、EKS `eks`、Fargate `fargate`、ECR `ecr` |
| Databases | `#C925D1` | Aurora `aurora`、RDS `rds`、DynamoDB `dynamodb`、ElastiCache `elasticache`、DocumentDB `documentdb_with_mongodb_compatibility`、MemoryDB `memorydb_for_redis`、Database Migration Service `database_migration_service` |
| Storage | `#7AA116` | S3 `s3`、EBS `elastic_block_store`、EFS `elastic_file_system`、FSx `fsx`、Backup `backup`、Storage Gateway `storage_gateway`、Elastic Disaster Recovery `cloudendure_disaster_recovery` |
| Networking & Content Delivery | `#8C4FFF` | CloudFront `cloudfront`、Route 53 `route_53`、Elastic Load Balancing `elastic_load_balancing`、API Gateway `api_gateway`、Transit Gateway `transit_gateway`、Direct Connect `direct_connect`、Site-to-Site VPN `site_to_site_vpn`、Client VPN `client_vpn`、PrivateLink `vpc_privatelink`、Global Accelerator `global_accelerator`、VPC Lattice `vpc_lattice` |
| Application Integration | `#E7157B` | SQS `sqs`、SNS `sns`、EventBridge `eventbridge`、Step Functions `step_functions`、AppSync `appsync`、MQ `mq` |
| Analytics | `#8C4FFF` | Athena `athena`、Glue `glue`、Kinesis Data Streams `kinesis_data_streams`、Data Firehose `kinesis_data_firehose`、OpenSearch Service `elasticsearch_service`、EMR `emr`、Redshift `redshift`、Lake Formation `lake_formation`、MSK `managed_streaming_for_kafka` |
| Management & Governance | `#E7157B` | CloudWatch `cloudwatch_2`、CloudTrail `cloudtrail`、Config `config`、Systems Manager `systems_manager`、CloudFormation `cloudformation`、Organizations `organizations`、Control Tower `control_tower`、Trusted Advisor `trusted_advisor` |
| Security, Identity & Compliance | `#DD344C` | IAM `identity_and_access_management`、IAM Identity Center `single_sign_on`、Cognito `cognito`、KMS `key_management_service`、Secrets Manager `secrets_manager`、Certificate Manager `certificate_manager_3`、WAF `waf`、Shield `shield`、Network Firewall `network_firewall`、Firewall Manager `firewall_manager`、GuardDuty `guardduty`、Security Hub `security_hub`、Inspector `inspector`、Macie `macie`、Directory Service `directory_service` |
| Artificial Intelligence | `#01A88D` | Bedrock `bedrock`、Bedrock AgentCore `bedrock_agentcore`、SageMaker AI `sagemaker`、Amazon Q `q` |
| Developer Tools | `#C925D1` | CodePipeline `codepipeline`、CodeBuild `codebuild`、CodeDeploy `codedeploy`、X-Ray `xray` |
| Migration & Modernization | `#01A88D` | DataSync `datasync`、Transfer Family `transfer_family`、Application Migration Service `cloudendure_migration` |
| Business Applications | `#DD344C` | SES `simple_email_service` |
| Front-End Web & Mobile | `#DD344C` | Amplify `amplify` |
| End User Computing | `#01A88D` | WorkSpaces `workspaces` |
| Internet of Things | `#7AA116` | IoT Core `iot_core` |
| Cloud Financial Management | `#7AA116` | Cost Explorer `cost_explorer`、Budgets `budgets_2` |

### リソースアイコン

テンプレートにリソースアイコンの例はないため、styleは次の形にする。サービスアイコンと違い、`shape`に名前を直接書き、`strokeColor=none`にする。ラベルはテンプレートと同じく、アイコンの下に別のテキスト要素で置く。大きさはサービスアイコンと同じ標準サイズにする。正方形でない図形も、絵の縦横比は保たれる。

```text
fontFamily=IPAPGothic;sketch=0;outlineConnect=0;fontColor=#232F3E;gradientColor=none;fillColor=<色>;strokeColor=none;html=1;aspect=fixed;shape=mxgraph.aws4.<名前>;
```

| カテゴリ | `fillColor` | リソースと名前 |
|---|---|---|
| Networking & Content Delivery | `#8C4FFF` | Application Load Balancer `application_load_balancer`、Network Load Balancer `network_load_balancer`、Gateway Load Balancer `gateway_load_balancer`、NAT Gateway `nat_gateway`、Internet Gateway `internet_gateway`、VPC エンドポイント `endpoints`、仮想プライベートゲートウェイ `vpn_gateway`、VPN 接続 `vpn_connection`、カスタマーゲートウェイ `customer_gateway`、Transit Gateway アタッチメント `transit_gateway_attachment`、VPC ピアリング接続 `peering`、ネットワーク ACL `network_access_control_list`、Elastic Network Interface `elastic_network_interface`、VPC フローログ `flow_logs`、Route 53 ホストゾーン `hosted_zone`、Route 53 Resolver `route_53_resolver` |
| Security, Identity & Compliance | `#DD344C` | Network Firewall エンドポイント `network_firewall_endpoints`、IAM ロール `role` |
| Management & Governance | `#E7157B` | Organizations アカウント `organizations_account`、Organizations OU `organizations_organizational_unit` |
| Compute | `#ED7100` | EC2 インスタンス `instance2`、Lambda 関数 `lambda_function`、Elastic IP アドレス `elastic_ip_address` |
| Containers | `#ED7100` | ECS サービス `ecs_service`、ECS タスク `ecs_task` |
| Databases | `#C925D1` | RDS インスタンス `rds_instance`、Aurora インスタンス `aurora_instance`、RDS Proxy `rds_proxy`、DynamoDB テーブル `table` |
| Storage | `#7AA116` | S3 バケット `bucket`、EBS ボリューム `volume`、EBS スナップショット `snapshot` |

### AWS以外の要素

AWS図の中に描くAWS以外の要素に使用する。styleはリソースアイコンと同じ形にする。`#242F3E`と`#232F3D`が混ざっているのは、公式パッケージのファイルの値どおりである。オンプレミスのネットワーク図では`onprem-guide.md`の図形を使用する。

| 要素 | `fillColor` | 名前 |
|---|---|---|
| 利用者(複数) | `#242F3E` | `users` |
| 利用者(1人) | `#242F3E` | `user` |
| クライアントPC | `#232F3D` | `client` |
| モバイル端末 | `#232F3D` | `mobile_client` |
| インターネット | `#232F3D` | `internet` |
| 事務所の建物 | `#232F3D` | `office_building` |
| オンプレミスのサーバー | `#232F3D` | `traditional_server` |
| サーバー(複数) | `#232F3D` | `servers` |
| AWS以外のデータベース | `#232F3D` | `generic_database` |
| AWS以外のアプリケーション | `#232F3D` | `generic_application` |
| AWS以外のファイアウォール | `#242F3E` | `generic_firewall` |

## 基本レイアウト

- ページサイズ: 1400×900
- タイトル: 左上、22ポイント
- AWS Cloud・AWSアカウント・リージョン境界名: 16ポイント
- サービス名・主要説明: 12〜14ポイント
- 注記・矢印ラベル・凡例: 11〜12ポイント
- 主要な処理方向: 左から右
- 入力元: AWS Cloud境界の左側
- 管理・暗号化・分析サービス: 主処理の右側または下側

図の内容が収まらない場合は文字を小さくせず、要素数を減らすかページサイズを見直す。

## 作成手順

1. 本ガイドと`aws-checklist.md`を読む。
2. 図の目的と読者が確認する判断事項を一文で定義する。
3. AWS Cloud、リージョン、ネットワークなど、実在する境界を先に配置する。
4. 主要な構成要素を左から右へ並べ、公式アイコンへ置き換える。アイコンの名前と色は「アイコン名」、置き場所は「サービスごとの描き方」に従う。
5. 実線と破線で接続関係を記載する。
6. 構造と線で表せず、判断を変える前提や対象外があるときだけ、装飾線のない通常テキストまたは番号付きコールアウトで追記する。なければ書かない。
7. draw.io元データを保存し、PNGを書き出す。XMLの書き方、線の接続点、線の経路とラベルは`drawio.md`に従う。
8. `aws-checklist.md`に沿ってPNGを目視確認する。

## 保存と書き出し

- draw.io元データとPNGは同じ基底名にする。
- draw.io元データを正とし、PNGは掲載用の派生成果物として扱う。
- Draw.io Desktopの`drawio`コマンドをPATHに通して使用する。AppImageの一時パスを通常手順に使用しない。
- PNGは`${CLAUDE_SKILL_DIR}/scripts/export-png.sh`で書き出す。デスクトップ環境では`drawio`、画面のない環境では`xvfb-run -a drawio --no-sandbox`をスクリプトが選択する。
- スクリプトはDraw.ioの出力を、左40ピクセル・上18ピクセルの余白で1400×900ピクセルの白背景へ配置し、出力寸法を検証する(いずれも環境変数で変更可。`drawio.md` 参照)。
- 書き出しには`drawio`、`ffmpeg`、`ffprobe`、`fontconfig`、`python3`、IPA Pゴシックが必要であり、画面のない環境では`xvfb-run`も必要とする。
- スクリプトを使用できない場合は、Draw.io Desktopからページ単位、余白0、拡大率100%でPNGを書き出し、1400×900ピクセルであることを確認する。
- PNGを書き出した後、解像度、文字切れ、線、アイコン、重なりを目視確認する。
