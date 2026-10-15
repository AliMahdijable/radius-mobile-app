# لوحة المشروع الوطنيّ (FTTH) — خريطة المسارات الشاملة

> مرجعٌ لبوّابة موزِّع **FTTH / المشروع الوطنيّ** (`admin.ftth.iq`) تمهيداً لدمجها في البرو.
> توثيقٌ فقط — لا تعديل على كود المشروع. آخر تحديث: ٢٠٢٦-١٠-١٥.
> **مصدر التأكيد:** بناء الواجهة + **HAR حيّ** (٢٧٤ طلباً، ٤٢ نقطة) من جلسة الموزّع.
> بيانات المشتركين في الأمثلة **معمّاة** (أسماء/هواتف/عناوين/MAC/IP ليست حقيقيّة).

---

## ١) نظرة عامّة

| البند | القيمة |
|---|---|
| بوّابة الموزّع (ويب) | `https://admin.ftth.iq/` |
| **قاعدة الـAPI العمليّة** | **`https://admin.ftth.iq/api/`** ← كلّ النداءات الحيّة هنا (نفس الأصل) |
| قاعدة مُعلَنة في الإعداد | `https://api.ftth.iq/api/` (`gw_api_base`) — العبّارة الأعلى؛ عمليّاً تُخاطَب عبر `admin.ftth.iq/api/` |
| المنصّة | **Angular** SPA، سمة `epaw`، خطّ Dubai، لغة `ar` |
| البناء المفحوص | `main.df9607ab6a10672e.js` (خادم ٢٠٢٦-١٠-١٤) |
| الدور | **Contractor** (المقاول = الموزّع)، خطّ العمل **Ftth** |
| الحساب المفحوص | partner `6204`، منطقتان `FBG0885-3` · `FBG0886-7` |
| تقارير (BI) | `https://dashboard.ftth.iq/superset/…` — Apache **Superset** |
| تتبّع الأخطاء | `https://elsentry.earthlink.iq/api/15/…` — **Sentry** (بنية EL مشترَكة، تيليمتري فقط) |

**مهمّ — منصّة ايرث لنك نفسها:** البناء يحمل مراجع `reseller.earthlink.iq`، وKeycloak `sso.earthlink.iq/realms/el_int`، ونظام تذاكر EL القديم `admin.earthlink.iq/Support/Tickets.aspx`. FTTH وEarthLink منتَجان على **منصّةٍ واحدة** يتفرّعان بـ`lineOfBusiness` (FTTH مقابل اللاسلكيّ). العبّارة REST **حديثة ونظيفة** (موارد: `subscriptions/{id}`, `customers/{id}` …) — أحدث من واجهة EL القديمة التي يخاطبها محوّلنا الحاليّ.

---

## ٢) المصادقة والدخول — **مؤكَّد**

**دخول الموزّع:**
```
POST https://admin.ftth.iq/api/auth/Contractor/token
Content-Type: application/x-www-form-urlencoded

grant_type=password & scope=openid profile & client_id= & username=<الهاتف> & password=<السرّ>
```
**الردّ:**
```jsonc
{ "access_token":"…", "refresh_token":"…", "token_type":"Bearer",
  "expires_in":3600, "refresh_expires_in":691200,
  "second_factor_required":false, "enrolledSecondFactorMethods":null }
```
- OAuth2 password grant (Keycloak خلفه، realm `el_int`). التوكن ساعة، التجديد ٨ أيّام.
- بعده: `Authorization: Bearer <access_token>` على كلّ النداءات.
- **2FA:** TOTP متاح (`second_factor_required` + `enrolledSecondFactorMethods`)؛ تذكير كلّ ١٤ يوماً.
- **المسارات العامّة (بلا توكن):** `/auth/login · forgot-password · reset-password · activation · agent_login`، و`/page/*`.

**`GET api/current-user`** → ملف الموزّع وصلاحيّاته:
```jsonc
{ "model": {
  "username":"07…", "email":"…", "impersonated":false,
  "permissions":[{"id","displayValue":"Can Query Zones"}, {"…":"Can Query Customers"}, …],
  "zones":[{"id":"FBG0885-3"}, {"id":"FBG0886-7"}],
  "hierarchyZones":[…], "subPartners":[],
  "roles":[{"displayValue":"Contractor"},{"displayValue":"manage-account"},{"…":"manage-account-links"}],
  "linesOfBusiness":[{"id":0,"displayValue":"Ftth"}],
  "self":{"id":"6204","displayValue":"<اسم الموزّع>"} } }
```

**`GET api/configurations`** → أعلام الميزات وبيانات العرض (مؤكَّد، مهمّ):
```jsonc
{ "model": {
  "subscriptionWillExpireInDays":7, "endSoonWhenSubscriptionExpiringInDays":5,
  "minimumSupportedAppVersion":null,
  "features":[ {"name":"AllowSosActivation","isEnabled":true},
               {"name":"AllowScheduleChangeForOnlinePayment","isEnabled":true},
               {"name":"AllowSpeedBooster","isEnabled":true} ],
  "referralRewardAmount":5000,
  "referralInfo":{"referralRewardAmount":5000,"maxAllowedReferrals":3,
                  "referralUsageResetPeriodInfo":{"type":"M","number":1}},
  "babylAiArScreenId":"…","babylAiEnScreenId":"…",
  "ticketScheduleInfo":{"maxUpdatesAllowed":3,"maxUpdateWindowInHours":24,
                        "workingHoursFromInUtc":6,"workingHoursToInUtc":20},
  "plansDisplayInfo":{ "BASIC":{"arabicName":"أساسي","speed":"60 Mbps"},
                       "PLUS":{"arabicName":"بلس","speed":"125 Mbps"},
                       "TURBO":{"arabicName":"تيربو","speed":"250 Mbps"},
                       "PRO MAX":{"arabicName":"برو ماكس","speed":"500 Mbps"},
                       "FIBER 35":"Basic 60", "FIBER 50":"Plus 125",
                       "FIBER 75":"Turbo 250", "FIBER 150":"Pro Max 500" },
  "speedBoosterInfo":{"allowedPlanForOffer":"FIBER 35","upgradedToPlan":"FIBER 50"} } }
```

> **ملاحظة «النقاط التشجيعيّة»:** لا يوجد في لوحة الموزّع قسم نقاط/ولاء. لكنّ الإعداد يحوي **مكافأة إحالة** (`referralReward` — ٥٠٠٠ د.ع، حدّ ٣ إحالات شهريّاً)، وهي ميزةٌ **موجَّهة للزبون** في تطبيق المشترك لا للموزّع — فهي متوافقة مع قولك إنّ لوحة المشروع بلا نقاط تشجيعيّة. (مثبَّتة هنا للدقّة فقط.)

---

## ٣) خريطة الـAPI الكاملة — **مؤكَّدة من HAR**

> كلّها تحت `https://admin.ftth.iq/api/`. الأفعال والردود مؤكَّدة ما لم يُذكر «متوقّع». `hierarchyLevel=0` شائع. الترقيم `pageSize` + `pageNumber` + `sortCriteria.property/direction`.

### ٣.١ اللوحة والملخّصات
| الطريقة | المسار | باراميترات / ردّ |
|---|---|---|
| GET | `partners/dashboard/summary` | `?hierarchyLevel=0` → customers{totalActive,totalInactive,totalExpiring,totalCount} + subscriptions{totalActive,totalExpiring,totalExpired,totalTrial,totalOnline,totalOffline,totalPendingMigration,totalCount} |
| GET | `customers/summary` | `?customerIds=…&customerIds=…` (متعدّد) → primaryPhone, customerType, id, displayValue |
| GET | `requests/summary` | `?hierarchyLevel=0` → totalOpen لكلّ نوع طلب |
| GET | `tasks/summary` | → totalOpen, totalCompleted, totalDueToday/ThisWeek/Next7, totalCount |
| GET | `announcements` · `announcements/latest` | `?isPinned&pageSize&pageNumber` → {id,title,body,publishedAt,imageUrl,linkUrl,linkTitle} |
| GET | `notifications` | `?onlyUnreadNotifications=true&pageSize&pageNumber` → {description,createdAt,isRead,readAt,templateId,self{id,displayValue}} |

### ٣.٢ الزبائن والبحث ومعلومات الاتصال
| الطريقة | المسار | باراميترات / ردّ |
|---|---|---|
| GET | `customers` | `?pageSize&pageNumber&sortCriteria.property=self.displayValue` (+ بحث متوقّع) → {self{id,displayValue}, primaryContact{self,mobile,email,secondaryPhone}, customerType, tags, createdAt} |
| GET | `customers/{id}` | → model{primaryContact{mobile,email}, addresses[{governorate,district,neighborhood,street,house,gpsCoordinate,displayValue}], customerType, usrReferralCode, self} |
| GET | `customers/{id}/tasks` | → مهام الزبون |
| GET | `customers/subscriptions` | `?customerId=…` → اشتراك الزبون كاملاً (نفس حقول §٣.٣ + deviceDetails) |
| GET | `customers/{id}/subscriptions/scheduled-changes` | التغييرات المجدولة |
| POST | `customers/{id}/subscriptions/scheduled-changes/cancel` | إلغاء (متوقّع) |
| GET | `addresses` | `?accountIds=…` (متعدّد) → **عنوان + جهاز**: zone, partner, customer, **deviceDetails{username, serial(ONT), fdt{id,displayValue}, fat{portNumber,id,displayValue}}**, governorate, district, neighborhood, street, house, apartment, nearestPoint, gpsCoordinate{lat,lng} |

### ٣.٣ الاشتراكات + العمليّات
| الطريقة | المسار | باراميترات / ردّ |
|---|---|---|
| GET | `subscriptions` | `?pageSize&pageNumber&sortCriteria.property=expires&status=Active&hierarchyLevel=0` → القائمة (مخطّط §٥) |
| GET | `subscriptions/{id}` | `?customerId=…` → applicableSubscription{planName,basePlanId,bundleId,variants}, customer, partner, zone, expiredAt, commitmentPeriodValue, autoRenew, salesType |
| GET | `subscriptions/statuses` | → `Active`(0) · `Expired`(1) |
| GET | `subscriptions/allowed-actions` | `?subscriptionIds=…` (متعدّد) → لكلّ اشتراك: `subscriptionId` + `allowedActions[]{id,displayValue}` + `actionsInfo[]{action, isAllowed, reasonToDecline{displayValue, additionalInfo{openOrderStatus, openTransferRequestId}}}` — **يحكم أزرار العمليّات وسبب تعطيلها** |
| GET | `subscriptions/trial` | `?…&status=Active` → الاشتراكات التجريبيّة |
| GET | `subscriptions/{id}/errors` | أخطاء الاشتراك |
| GET | `subscriptions/{id}/sessions/total-usage` | → totalDownloadedBytes, totalUploadedBytes, totalNumberOfSessions, currentServiceCycleUsage{used,remaining,totalQuota} |
| GET | `subscriptions/{id}/sessions/period-usage` | `?periodStartedAt&periodSize=12&itemType=0` → استهلاك شهريّ [{up,down,lastSessionOccurredAt,sessionsCount,avgDuration}] |
| GET | `sessions` | `?pageSize&pageNumber&sortCriteria.property=username&status=1` → {subscription,zone,partner,status(Online0/Offline1),customer,username,ipAddress,macAddress,bytes,sessionTime} |
| POST | `subscriptions/purchase` | **شراء/تفعيل** — الجسم متوقّع (لم يُلتقَط؛ راجع §٦) |
| POST | `subscriptions/calculate-price` | حساب السعر — متوقّع |
| POST | `subscriptions/confirm-payment` | تأكيد الدفع — متوقّع |
| POST | `subscriptions/{id}/change` · `/extend` · `/suspend` · `/unsuspend` · `/disconnect` | عمليّات — أجسامها متوقّعة |
| POST | `subscriptions/{id}/grace/purchase-and-extend` · `/purchase-extra-quota` · `/sos-activate` | متوقّع |
| GET | `subscriptions/{id}/sos-status` · `/device` · `/device/ont` | متوقّع |

### ٣.٤ الباقات
| الطريقة | المسار | ردّ |
|---|---|---|
| GET | `plans/bundles` | `?includePrices=false` → bundle `FTTH_BASIC` + applicableSubscriptions[{planName,basePlanId,bundleId,price{value,currency},billingPrice,speed,variants[Base/Vas],title,imageUrl,isQuotaBased}] |
| GET | `plans/services` | الخدمات (متوقّع) |

الباقات: **Basic 60 · Plus 125 · Turbo 250 · Pro Max 500** (Mbps). خدمات مضافة (VAS): **IPTV · Parental Control**.

### ٣.٥ المحفظة والرصيد والحركات + **طرق الدفع**
| الطريقة | المسار | باراميترات / ردّ |
|---|---|---|
| GET | `partners/{id}/wallets/balance` | → {commission, teamMemberWallet, **balance**, totalCredit, remainingCredit, currency:"IQD"} |
| GET | `transactions` | `?pageSize&pageNumber&walletType=Main&walletOwnerType=Partner&partnerId=6204&hierarchyLevel=1&sortCriteria.property=occuredAt` |
| GET | `transactions/revenue` | `?pageSize&pageNumber&createdAt.from&createdAt.to&sortCriteria.property=occuredAt` → [{salesGroup,transactionAmount,remainingBalance,occuredAt,**type**:PLAN_RENEW,paymentMode,paymentMethod,subscription{startsAt,endsAt,id},discountType,discountAmount,deviceUsername,customer,walletOwnerType}] |
| GET | `transactions/revenue/statistics` | `?createdAt.from&createdAt.to` → {totalRevenue{value,currency}} |
| GET | `transactions/payment-methods` | `?subscriptionsIds=…` (متعدّد) → لكلّ اشتراك paymentMethod: **Wallet(0)** · **Card(1)** |
| POST | `wallets/transfer-funds` · `wallets/transfer-target-users` | تحويل رصيد — متوقّع |
| POST | `partners/{id}/wallets/top-up` · `/transfer-commission` | شحن/عمولة — متوقّع |
| POST | `teams/members/{id}/wallet-refill` | تعبئة محفظة عضو — متوقّع |

**طرق الدفع (enum مؤكَّد): `Wallet`(0) · `Card`(1).** الـ«Card» = الدفع بالبطاقة (تبادل/فيزا/ماستر — `isTabadulPaymentAvailble:true`، صفحة `/page/tabadul-payment-status`). «الرصيد» في طلبك = رصيد المحفظة. تدفّق الدفع بالبطاقة يمرّ بـ`confirm-payment` بعد العودة من البوّابة. (أجسام الشراء لم تُلتقَط بعد.)

### ٣.٦ الطلبات (تسجيل/نقل/عنوان/ترحيل)
| الطريقة | المسار | ردّ |
|---|---|---|
| GET | `requests` | `?…&typeIds=<uuid>&status=Open&additionalFilters=MyPartnersRequests&additionalFilters=MyRequests` |
| GET | `requests/types` | ٨ أنواع: Customer Onboarding · New Address Onboarding · Wireless Customer Onboarding · Subscription Transfer · … |
| GET | `requests/statuses` | New · Error · Done (+Canceled/InProgress) |
| GET | `requests/summary` | totalOpen لكلّ نوع |
| POST/GET | `requests/customer-onboarding` (+`/{id}`, `/industries`, `/installation-options`, `/validate-national-id`) | تسجيل زبون — متوقّع |
| POST/GET | `requests/subscription-transfer` (+`/{id}`, `/reasons`) · `requests/customer-address` (+`/{id}`) | متوقّع |
| POST/GET | `requests/legacy-subscription-migration` (+`/{id}`, `/zones`) · `requests/update-contact/{id}` · `requests/otp-validation` | متوقّع |
| POST | `orders/cancel` · `v2/requests` | متوقّع |

### ٣.٧ المهام والتدقيق وعناصر الشبكة والفريق
| الطريقة | المسار | ردّ |
|---|---|---|
| GET | `tasks` | `?…&status=0&sortCriteria.property=dueAt` |
| GET | `tasks/types` | Connect Customer · Sign Contract · Maintenance |
| GET | `audit-logs` | `?pageSize&pageNumber&sortCriteria.property=CreatedAt` → [{id,eventType,actor{username,ipAddress,accountType:Partner},amount,isMonetary,isSuccessful,createdAt}] |
| GET | `audit-logs/event-types` | ٨٢ نوعاً (AccountActivation, ActivateAccount, …) |
| GET | `audit-logs/summary` | {totalAmount} |
| GET | `locations/zones` | → [{self{id:"FBG0885-3",displayValue}}] |
| GET | `governorates` · `network-elements/fats` · `/fdts` · `/ont-vendors` | متوقّع (FAT/FDT ظهرا داخل `addresses.deviceDetails`) |
| GET/POST | `teams/members` (+`/{id}`, `/admin-user`, `/validate-username`, `/{id}/reset-2fa`, `/{id}/wallet-refill`) · `teams/roles` | متوقّع |
| GET/POST | `partners` (+`/{id}`, `/lookups`, `/activations`, `/activations/username-unique-status`) | متوقّع |

---

## ٤) قسم التذاكر — **مؤكَّد**

| الطريقة | المسار | باراميترات / ردّ |
|---|---|---|
| GET | `support/tickets` | `?pageSize=12&pageNumber=1&sortCriteria.property=createdAt&sortCriteria.direction=desc&hierarchyLevel=0&additionalFilter=ForMe` → {totalCount:268, items[]} |
| GET | `support/tickets/statuses` | **New · In progress · Resolved · Closed · Canceled** (١٠ إجمالاً، id=UUID) |
| GET | `support/tickets/{id}` | تفاصيل — متوقّع |
| GET/POST | `support/tickets/{id}/comments` · `/attachments` | متوقّع (يفسّر `commentsCount`/`attachmentsCount`) |
| POST | `support/tickets` · `support/tickets/{id}/status` | إنشاء/تغيير حالة — متوقّع |

**مخطّط التذكرة (مؤكَّد):**
```jsonc
{ "self":{"id":"<uuid>","displayValue":"<عنوان التذكرة>"},
  "displayId":"P-26101410324208854",      // P- = من الموزّع/اللوحة ، cc- = مركز الاتصال
  "summary":"<متن حرّ عربيّ، أو منظَّم من وكيل ذكاء>",
  "status":"Closed",
  "customer":{"id":"…","displayValue":"…"},   // «Our company» (id 1721438) = تذكرة بنية تحتيّة لا تخصّ مشتركاً
  "partner":{"id":"6204","displayValue":"<الموزّع>"},  // قد يكون null
  "zone":{"id":"FBG0886-7","displayValue":"…"},        // قد يكون null
  "attachmentsCount":0, "commentsCount":0,
  "createdAt":"…Z", "updatedAt":"…Z" }
```
**قواعد التذاكر (من `configurations.ticketScheduleInfo`):** حدّ ٣ تحديثات / ٢٤ ساعة، ساعات العمل ٦→٢٠ UTC (٩→٢٣ بغداد).
**تصنيفات ومفاهيم:** انقطاع/ضعف خدمة · استفسار · بور عالي · مشكلة كابينة · تجييك عامود؛ ومفاهيم فايبر: بور FAT بالـdBm، LOS، rx power، الزون. **وكيل Babyl AI** يفتح تذاكر آليّاً بمتن منظَّم (تصنيف، UserBrimId، planName، username، expiration، status، rx power).
**بديل قديم:** نظام ايرث لنك `admin.earthlink.iq/Support/Tickets.aspx`.

---

## ٥) نماذج البيانات المؤكَّدة

**الاشتراك (`subscriptions`/`customers/subscriptions`):**
```
username (FBG885F15P2) · bundleId (FTTH_BASIC) · bundle · status (Active/Expired)
services[] (Base:BASIC + Vas:IPTV,PARENTAL_CONTROL) · salesType (Upfront)
customer{id,displayValue} · partner{id} · zone{id}
expires · startedAt · commitmentPeriod · autoRenew · autoRenewPaymentMethod
hasActiveSession · macAddress · lockedMac · ipAddress · isSuspended · suspensionReason
isQuotaBased · totalQuotaInBytes · publicIpsCount · lineOfBusiness (Ftth)
activeSession{startedAt,sessionTimeInSeconds,ipAddress}
deviceDetails{username, serial(ONT), fdt{id,displayValue}, fat{portNumber,id,displayValue}}
```
**الزبون (`customers`/`customers/{id}`):** self{id,displayValue} · primaryContact{mobile,email,secondaryPhone} · customerType (Residential0) · addresses[] · usrReferralCode · tags · createdAt.
**حركة الإيراد (`transactions/revenue`):** type (PLAN_RENEW…) · transactionAmount{value,currency} · occuredAt · paymentMode/paymentMethod (Wallet/Card) · subscription{startsAt,endsAt,id} · discountAmount · deviceUsername · customer · walletOwnerType (Customer/Partner).
**محفظة الموزّع:** balance · commission · totalCredit · remainingCredit · teamMemberWallet · currency.

**تعدادات (enums) مؤكَّدة:** subscription status Active(0)/Expired(1) · session Online(0)/Offline(1) · paymentMethod Wallet(0)/Card(1) · customerType Residential(0) · ticket statuses (New/In progress/Resolved/Closed/Canceled…) · request statuses (New/Error/Done/Canceled) · roles (Contractor/manage-account) · lineOfBusiness Ftth(0).

---

## ٦) ما يبقى لالتقاطه (أجسام الكتابة)

الـHAR كان تصفّحاً للقراءة — عمليّات الكتابة لم تُنفَّذ فلم تُلتقَط أجسامها. تُكمَّل حين تُنفَّذ فعلاً (لا عمليّة وهميّة تكلّف مال):
- `subscriptions/purchase` + `confirm-payment` + تدفّق **البطاقة/التبادل** · `calculate-price`
- `subscriptions/{id}/change · extend · suspend · unsuspend · disconnect · purchase-extra-quota · sos-activate`
- `wallets/transfer-funds` · `partners/{id}/wallets/top-up` · `transfer-commission`
- تذاكر: `POST support/tickets` · `/{id}/comments` · `/{id}/status` · `support/tickets/{id}` (تفاصيل)
- طلبات التسجيل: `customer-onboarding` (+`validate-national-id`, `installation-options`)

> فيديوا سطح المكتب `errro-creat.mp4` / `nonlogin.mp4` قد يوثّقان خطأ إنشاء/حالة غير مسجّلة — أراجعهما عند الطلب.

---

## ٧) مطابقةٌ مختصرة مع مشروعنا (للسياق — لا دمج الآن)

محوّلنا الحاليّ لإيرث لنك (`/api/v2/el/*`، يتفرّع على `kind='earthlink'` في `sas_servers`) هو **قالب** محوّل FTTH مستقبلاً (`kind='ftth'` على `admin.ftth.iq/api/`).

| قدرة FTTH | ما يقابلها عندنا (EL) |
|---|---|
| `auth/Contractor/token` (+ refresh) | تدفّق دخول الساس + `provider` في `/api/auth/me` |
| `subscriptions` + `/{id}` + عمليّاتها | تفاصيل المشترك + التفعيل/التمديد/تغيير الباقة |
| `transactions/payment-methods` (Wallet/Card) | طرق التفعيل (محفظة/رصيد/كارت) — البطاقة/التبادل جديد |
| `partners/{id}/wallets/balance` + `transfer-funds` | الرصيد + `el/transfer`/`transfer-targets` |
| `transactions/revenue` + `/statistics` | كشف الحساب `el/account-statement` + التقارير |
| `customers` + `addresses`(ONT/FAT/FDT) | البحث + تفاصيل المشترك (الفايبر جديد) |
| `plans/bundles` | الباقات + أسعار المشترك |
| **التذاكر** + `audit-logs` + `tasks` | **لا مقابل** — أقسام جديدة |

---

## ٨) ملاحظات الاستخراج (الشفافيّة)

- **المصدر:** بناء `admin.ftth.iq/main.df9607ab6a10672e.js` + **HAR حيّ** زوّده المستخدم (٢٧٤ طلباً، ٤٢ نقطة فريدة، جلسة قراءة).
- **قاعدة واحدة عمليّاً:** كلّ النداءات على `admin.ftth.iq/api/` (الإعداد يُعلن `api.ftth.iq/api/` كعبّارة أعلى).
- **مؤكَّد:** الدخول، current-user/الصلاحيّات، configurations، ٤٢ نقطة GET بردودها، التذاكر وحالاتها، نماذج البيانات والتعدادات.
- **متوقّع (ينتظر التقاطاً):** أجسام الـPOST (الشراء/العمليّات/التحويل/التذاكر)، ومسارات لم تظهر في جلسة القراءة (network-elements, teams, partners/activations, onboarding).
- **تأكيد:** الـHAR فيه ١٥ POST فقط = ١ دخول + ١٤ تيليمتري Sentry (`elsentry.earthlink.iq/api/15/envelope`)؛ **لا عمليّة أعمالٍ كاتبة** فيه. و`dashboard.ftth.iq` = Superset للتقارير.
- بيانات المشتركين **معمّاة** في هذا الملفّ، والملحق أدناه أسماء حقول وأنواع فقط. لم يُجرِ المساعد دخولاً حيّاً ولا أيّ كتابة؛ الالتقاط زوّده المستخدم.

---

## ملحق أ) المخطّطات الكاملة (من HAR — أسماء حقول وأنواع فقط، بلا بيانات)

> مُكثَّف: حُذف `.entityType` و`.description` من كائنات المرجع (كلّها تحمل `{id,displayValue,entityType,description}`). `[]`=مصفوفة، `null`=ظهر فارغاً في العيّنة.


**GET /api/addresses**
- `items[]` · []
- `items[].apartment` · null
- `items[].city` · null
- `items[].customer.displayValue` · string
- `items[].customer.id` · string
- `items[].customer.type` · int
- `items[].deviceDetails.fat.displayValue` · string
- `items[].deviceDetails.fat.id` · string
- `items[].deviceDetails.fat.portNumber` · null
- `items[].deviceDetails.fdt.displayValue` · string
- `items[].deviceDetails.fdt.id` · string
- `items[].deviceDetails.serial` · string
- `items[].deviceDetails.username` · string
- `items[].displayValue` · string
- `items[].district.displayValue` · string
- `items[].district.id` · string
- `items[].governorate.displayValue` · string
- `items[].governorate.id` · string
- `items[].gpsCoordinate.latitude` · num
- `items[].gpsCoordinate.longitude` · num
- `items[].house` · int
- `items[].id` · string
- `items[].nearestPoint` · string
- `items[].neighborhood` · string
- `items[].partner.displayValue` · string
- `items[].partner.id` · string
- `items[].partner.type` · int
- `items[].street` · int
- `items[].zone.displayValue` · string
- `items[].zone.id` · string
- `items[].zone.zoneAccessibleToLoggedInPartner` · bool
- `totalCount` · int

**GET /api/announcements**
- `items[]` · []
- `items[].body` · string
- `items[].id` · int
- `items[].imageUrl` · null
- `items[].isPinned` · bool
- `items[].linkTitle` · string
- `items[].linkUrl` · string
- `items[].publishedAt` · string
- `items[].title` · string
- `totalCount` · int

**GET /api/announcements/latest**
- `items[]` · []
- `items[].body` · string
- `items[].id` · int
- `items[].imageUrl` · null
- `items[].isPinned` · bool
- `items[].linkTitle` · string
- `items[].linkUrl` · string
- `items[].publishedAt` · string
- `items[].title` · string
- `totalCount` · int

**GET /api/audit-logs**
- `items[]` · []
- `items[].actor.accountType.displayValue` · string
- `items[].actor.accountType.id` · int
- `items[].actor.ipAddress` · string
- `items[].actor.username` · string
- `items[].amount` · null
- `items[].createdAt` · string
- `items[].customer` · null
- `items[].customer.displayValue` · string
- `items[].customer.id` · string
- `items[].eventType` · string
- `items[].id` · string
- `items[].isMonetary` · bool
- `items[].isSuccessful` · bool
- `items[].walletOwnerType` · null
- `items[].walletOwnerType.displayValue` · string
- `items[].walletOwnerType.id` · int
- `items[].zone` · null
- `items[].zone.displayValue` · string
- `items[].zone.id` · string
- `totalCount` · int

**GET /api/audit-logs/event-types**
- `items[]` · []
- `items[].displayValue` · string
- `totalCount` · int

**GET /api/audit-logs/summary**
- `model.totalAmount` · num

**GET /api/configurations**
- `model.babylAiArScreenId` · string
- `model.babylAiEnScreenId` · string
- `model.endSoonWhenSubscriptionExpiringInDays` · int
- `model.endSoonWhenVoucherExpiringInDays` · int
- `model.features[]` · []
- `model.features[].isEnabled` · bool
- `model.features[].name` · string
- `model.minimumSupportedAppVersion` · null
- `model.plansDisplayInfo.BASIC.arabicName` · string
- `model.plansDisplayInfo.BASIC.englishName` · string
- `model.plansDisplayInfo.BASIC.speed` · string
- `model.plansDisplayInfo.FIBER 150.arabicName` · string
- `model.plansDisplayInfo.FIBER 150.englishName` · string
- `model.plansDisplayInfo.FIBER 150.speed` · string
- `model.plansDisplayInfo.FIBER 35.arabicName` · string
- `model.plansDisplayInfo.FIBER 35.englishName` · string
- `model.plansDisplayInfo.FIBER 35.speed` · string
- `model.plansDisplayInfo.FIBER 50.arabicName` · string
- `model.plansDisplayInfo.FIBER 50.englishName` · string
- `model.plansDisplayInfo.FIBER 50.speed` · string
- `model.plansDisplayInfo.FIBER 75.arabicName` · string
- `model.plansDisplayInfo.FIBER 75.englishName` · string
- `model.plansDisplayInfo.FIBER 75.speed` · string
- `model.plansDisplayInfo.PLUS.arabicName` · string
- `model.plansDisplayInfo.PLUS.englishName` · string
- `model.plansDisplayInfo.PLUS.speed` · string
- `model.plansDisplayInfo.PRO MAX.arabicName` · string
- `model.plansDisplayInfo.PRO MAX.englishName` · string
- `model.plansDisplayInfo.PRO MAX.speed` · string
- `model.plansDisplayInfo.TURBO.arabicName` · string
- `model.plansDisplayInfo.TURBO.englishName` · string
- `model.plansDisplayInfo.TURBO.speed` · string
- `model.referralInfo.maxAllowedReferrals` · int
- `model.referralInfo.referralRewardAmount` · int
- `model.referralInfo.referralUsageResetPeriodInfo.number` · int
- `model.referralInfo.referralUsageResetPeriodInfo.type` · string
- `model.referralRewardAmount` · int
- `model.speedBoosterInfo.allowedPlanForOffer` · string
- `model.speedBoosterInfo.upgradedToPlan` · string
- `model.subscriptionWillExpireInDays` · int
- `model.ticketScheduleInfo.maxUpdateWindowInHours` · int
- `model.ticketScheduleInfo.maxUpdatesAllowed` · int
- `model.ticketScheduleInfo.workingHoursFromInUtc` · int
- `model.ticketScheduleInfo.workingHoursToInUtc` · int

**GET /api/current-user**
- `model.email` · string
- `model.firstName` · null
- `model.hierarchyZones[]` · []
- `model.hierarchyZones[].displayValue` · string
- `model.hierarchyZones[].id` · string
- `model.impersonated` · bool
- `model.isRootPartnerImpersonated` · bool
- `model.languages` · null
- `model.linesOfBusiness[]` · []
- `model.linesOfBusiness[].displayValue` · string
- `model.linesOfBusiness[].id` · int
- `model.permissions[]` · []
- `model.permissions[].displayValue` · string
- `model.permissions[].id` · string
- `model.roles[]` · []
- `model.roles[].displayValue` · string
- `model.roles[].id` · int
- `model.self.displayValue` · string
- `model.self.id` · string
- `model.subPartners[]` · []
- `model.username` · string
- `model.zones[]` · []
- `model.zones[].displayValue` · string
- `model.zones[].id` · string

**GET /api/customers**
- `items[]` · []
- `items[].accountImageUrl` · null
- `items[].createdAt` · string
- `items[].customerType.displayValue` · string
- `items[].customerType.id` · int
- `items[].primaryContact.email` · null
- `items[].primaryContact.mobile` · null
- `items[].primaryContact.secondaryPhone` · null
- `items[].primaryContact.self.displayValue` · string
- `items[].primaryContact.self.id` · string
- `items[].self.displayValue` · string
- `items[].self.id` · string
- `items[].status` · null
- `items[].tags[]` · []
- `totalCount` · int

**GET /api/customers/subscriptions**
- `items[]` · []
- `items[].activeSession.ipAddress` · string
- `items[].activeSession.macAddress` · string
- `items[].activeSession.sessionTimeInSeconds` · int
- `items[].activeSession.startedAt` · string
- `items[].autoRenew` · bool
- `items[].autoRenewPaymentMethod` · null
- `items[].bundle.displayValue` · string
- `items[].bundle.id` · string
- `items[].bundleId` · string
- `items[].commitmentPeriod` · int
- `items[].customer.displayValue` · string
- `items[].customer.id` · string
- `items[].deviceDetails.fat.displayValue` · string
- `items[].deviceDetails.fat.id` · string
- `items[].deviceDetails.fat.portNumber` · null
- `items[].deviceDetails.fdt.displayValue` · string
- `items[].deviceDetails.fdt.id` · string
- `items[].deviceDetails.serial` · string
- `items[].deviceDetails.username` · string
- `items[].expires` · string
- `items[].hasActiveSession` · bool
- `items[].hasDifferentBillingPrice` · bool
- `items[].ipAddress` · string
- `items[].isPending` · bool
- `items[].isQuotaBased` · bool
- `items[].isSuspended` · bool
- `items[].isTrial` · bool
- `items[].lineOfBusiness.displayValue` · string
- `items[].lineOfBusiness.id` · int
- `items[].lockedMac` · null
- `items[].macAddress` · string
- `items[].openOnboardingRequest` · null
- `items[].partner.displayValue` · string
- `items[].partner.id` · string
- `items[].publicIpsCount` · null
- `items[].salesType.displayValue` · string
- `items[].salesType.id` · int
- `items[].self.displayValue` · string
- `items[].self.id` · string
- `items[].services[]` · []
- `items[].services[].displayValue` · string
- `items[].services[].id` · string
- `items[].services[].productType.displayValue` · string
- `items[].services[].productType.id` · int
- `items[].services[].type.displayValue` · string
- `items[].services[].type.id` · int
- `items[].startedAt` · string
- `items[].status` · string
- `items[].suspensionReason` · null
- `items[].totalQuotaInBytes` · null
- `items[].zone.displayValue` · string
- `items[].zone.id` · string
- `totalCount` · int

**GET /api/customers/summary**
- `items[]` · []
- `items[].customerType.displayValue` · string
- `items[].customerType.id` · int
- `items[].displayValue` · string
- `items[].id` · string
- `items[].primaryPhone` · null
- `items[].secondaryPhone` · null
- `totalCount` · int

**GET /api/customers/{id}**
- `model.accountImageUrl` · null
- `model.accountType` · null
- `model.addresses[]` · []
- `model.addresses[].apartment` · null
- `model.addresses[].city` · null
- `model.addresses[].displayValue` · string
- `model.addresses[].district.displayValue` · string
- `model.addresses[].district.id` · string
- `model.addresses[].governorate.displayValue` · string
- `model.addresses[].governorate.id` · string
- `model.addresses[].gpsCoordinate.latitude` · num
- `model.addresses[].gpsCoordinate.longitude` · num
- `model.addresses[].house` · int
- `model.addresses[].id` · string
- `model.addresses[].nearestPoint` · null
- `model.addresses[].neighborhood` · string
- `model.addresses[].street` · int
- `model.customerType.displayValue` · string
- `model.customerType.id` · int
- `model.primaryContact.email` · null
- `model.primaryContact.mobile` · string
- `model.primaryContact.secondaryPhone` · null
- `model.primaryContact.self.displayValue` · string
- `model.primaryContact.self.id` · string
- `model.self.displayValue` · string
- `model.self.id` · string
- `model.status` · null
- `model.usrReferralCode` · string

**GET /api/customers/{id}/subscriptions/scheduled-changes**
- `items[]` · []
- `totalCount` · int

**GET /api/customers/{id}/tasks**
- `items[]` · []
- `totalCount` · int

**GET /api/locations/zones**
- `items[]` · []
- `items[].self.displayValue` · string
- `items[].self.id` · string
- `totalCount` · int

**GET /api/notifications**
- `details[]` · []
- `errorCode` · int
- `items[]` · []
- `items[].createdAt` · string
- `items[].data` · null
- `items[].isRead` · bool
- `items[].readAt` · null
- `items[].self.displayValue` · string
- `items[].self.id` · string
- `items[].templateId` · string
- `requestId` · string
- `title` · string
- `totalCount` · int
- `type` · string

**GET /api/partners/dashboard/summary**
- `model.customers.totalActive` · int
- `model.customers.totalCount` · int
- `model.customers.totalExpiring` · int
- `model.customers.totalInactive` · int
- `model.subscriptions.partnerManagedTotal` · int
- `model.subscriptions.partnerManagedWithoutTransferRequest` · int
- `model.subscriptions.totalActive` · int
- `model.subscriptions.totalCount` · int
- `model.subscriptions.totalExpired` · int
- `model.subscriptions.totalExpiring` · int
- `model.subscriptions.totalOffline` · int
- `model.subscriptions.totalOnline` · int
- `model.subscriptions.totalPendingMigration` · int
- `model.subscriptions.totalTrial` · int

**GET /api/partners/{id}/wallets/balance**
- `model.balance` · num
- `model.commission` · num
- `model.currency` · string
- `model.remainingCredit` · num
- `model.teamMemberWallet` · null
- `model.totalCredit` · num

**GET /api/plans/bundles**
- `items[]` · []
- `items[].applicableServices[]` · []
- `items[].applicableSubscriptionsNames[]` · []
- `items[].applicableSubscriptions[]` · []
- `items[].applicableSubscriptions[].basePlanId` · string
- `items[].applicableSubscriptions[].billingPrice.currency` · string
- `items[].applicableSubscriptions[].billingPrice.value` · num
- `items[].applicableSubscriptions[].bundleId` · string
- `items[].applicableSubscriptions[].hasDifferentBillingPrice` · bool
- `items[].applicableSubscriptions[].imageUrl` · string
- `items[].applicableSubscriptions[].isQuotaBased` · bool
- `items[].applicableSubscriptions[].lineOfBusiness.displayValue` · string
- `items[].applicableSubscriptions[].lineOfBusiness.id` · int
- `items[].applicableSubscriptions[].offers[]` · []
- `items[].applicableSubscriptions[].planName` · string
- `items[].applicableSubscriptions[].price.currency` · string
- `items[].applicableSubscriptions[].price.value` · num
- `items[].applicableSubscriptions[].speed` · string
- `items[].applicableSubscriptions[].title` · string
- `items[].applicableSubscriptions[].variants[]` · []
- `items[].applicableSubscriptions[].variants[].displayValue` · string
- `items[].applicableSubscriptions[].variants[].id` · string
- `items[].applicableSubscriptions[].variants[].productType.displayValue` · string
- `items[].applicableSubscriptions[].variants[].productType.id` · int
- `items[].applicableSubscriptions[].variants[].type.displayValue` · string
- `items[].applicableSubscriptions[].variants[].type.id` · int
- `items[].commitmentPeriods[]` · []
- `items[].lineOfBusiness.displayValue` · string
- `items[].lineOfBusiness.id` · int
- `items[].offers[]` · []
- `items[].price.currency` · string
- `items[].price.value` · num
- `items[].publicIpsCounts[]` · []
- `items[].self.displayValue` · string
- `items[].self.id` · string
- `items[].welcomePeriod` · int
- `totalCount` · int

**GET /api/requests**
- `items[]` · []
- `totalCount` · int

**GET /api/requests/statuses**
- `items[]` · []
- `items[].displayValue` · string
- `items[].id` · string
- `totalCount` · int

**GET /api/requests/summary**
- `items[]` · []
- `items[].displayValue` · string
- `items[].id` · string
- `items[].totalOpen` · int
- `items[].type.displayValue` · string
- `items[].type.id` · int
- `totalCount` · int

**GET /api/requests/types**
- `items[]` · []
- `items[].displayValue` · string
- `items[].id` · string
- `totalCount` · int

**GET /api/sessions**
- `items[]` · []
- `items[].createdAt` · null
- `items[].customer.displayValue` · string
- `items[].customer.id` · string
- `items[].ipAddress` · null
- `items[].macAddress` · null
- `items[].partner.displayValue` · string
- `items[].partner.id` · string
- `items[].sessionTimeInSeconds` · null
- `items[].status.displayValue` · string
- `items[].status.id` · int
- `items[].subscription.displayValue` · string
- `items[].subscription.id` · string
- `items[].subscription.isExpired` · bool
- `items[].totalDownloadedBytes` · int
- `items[].totalUploadedBytes` · int
- `items[].username` · string
- `items[].zone.displayValue` · string
- `items[].zone.id` · string
- `totalCount` · int

**GET /api/subscriptions**
- `items[]` · []
- `items[].activeSession` · null
- `items[].activeSession.ipAddress` · string
- `items[].activeSession.macAddress` · string
- `items[].activeSession.sessionTimeInSeconds` · int
- `items[].activeSession.startedAt` · string
- `items[].autoRenew` · bool
- `items[].autoRenewPaymentMethod` · null
- `items[].bundle.displayValue` · string
- `items[].bundle.id` · string
- `items[].bundleId` · string
- `items[].commitmentPeriod` · int
- `items[].customer.displayValue` · string
- `items[].customer.id` · string
- `items[].expires` · string
- `items[].hasActiveSession` · bool
- `items[].ipAddress` · string
- `items[].isQuotaBased` · bool
- `items[].isSuspended` · bool
- `items[].lineOfBusiness.displayValue` · string
- `items[].lineOfBusiness.id` · int
- `items[].lockedMac` · null
- `items[].macAddress` · string
- `items[].partner.displayValue` · string
- `items[].partner.id` · string
- `items[].publicIpsCount` · null
- `items[].salesType.displayValue` · string
- `items[].salesType.id` · int
- `items[].self.displayValue` · string
- `items[].self.id` · string
- `items[].services[]` · []
- `items[].services[].displayValue` · string
- `items[].services[].id` · string
- `items[].services[].productType.displayValue` · string
- `items[].services[].productType.id` · int
- `items[].services[].type.displayValue` · string
- `items[].services[].type.id` · int
- `items[].startedAt` · string
- `items[].status` · string
- `items[].suspensionReason` · null
- `items[].totalQuotaInBytes` · null
- `items[].username` · string
- `items[].zone.displayValue` · string
- `items[].zone.id` · string
- `totalCount` · int

**GET /api/subscriptions/allowed-actions**
- `items[]` · []
- `items[].actionsInfo[]` · []
- `items[].actionsInfo[].action.displayValue` · string
- `items[].actionsInfo[].action.id` · int
- `items[].actionsInfo[].isAllowed` · bool
- `items[].actionsInfo[].reasonToDecline` · null
- `items[].actionsInfo[].reasonToDecline.additionalInfo.openOrderStatus` · null
- `items[].actionsInfo[].reasonToDecline.additionalInfo.openTransferRequestId` · null
- `items[].actionsInfo[].reasonToDecline.displayValue` · string
- `items[].actionsInfo[].reasonToDecline.id` · int
- `items[].allowedActions[]` · []
- `items[].allowedActions[].displayValue` · string
- `items[].allowedActions[].id` · int
- `items[].subscriptionId` · string
- `totalCount` · int

**GET /api/subscriptions/statuses**
- `items[]` · []
- `items[].displayValue` · string
- `items[].id` · string
- `totalCount` · int

**GET /api/subscriptions/trial**
- `items[]` · []
- `totalCount` · int

**GET /api/subscriptions/{id}**
- `model.address` · null
- `model.applicableSubscription.basePlanId` · string
- `model.applicableSubscription.billingPrice` · null
- `model.applicableSubscription.bundleId` · string
- `model.applicableSubscription.hasDifferentBillingPrice` · bool
- `model.applicableSubscription.lineOfBusiness.displayValue` · null
- `model.applicableSubscription.lineOfBusiness.id` · int
- `model.applicableSubscription.planName` · string
- `model.applicableSubscription.price` · null
- `model.applicableSubscription.speed` · null
- `model.applicableSubscription.variants[]` · []
- `model.applicableSubscription.variants[].displayValue` · string
- `model.applicableSubscription.variants[].id` · string
- `model.applicableSubscription.variants[].productType.displayValue` · string
- `model.applicableSubscription.variants[].productType.id` · int
- `model.applicableSubscription.variants[].type.displayValue` · string
- `model.applicableSubscription.variants[].type.id` · int
- `model.autoRenew` · bool
- `model.autoRenewPaymentMethod` · null
- `model.commitmentPeriodValue` · int
- `model.customer.displayValue` · string
- `model.customer.id` · string
- `model.expiredAt` · string
- `model.lineOfBusiness.displayValue` · string
- `model.lineOfBusiness.id` · int
- `model.partner.displayValue` · string
- `model.partner.id` · string
- `model.publicIpsCount` · null
- `model.salesType.displayValue` · string
- `model.salesType.id` · int
- `model.zone.displayValue` · string
- `model.zone.id` · string

**GET /api/subscriptions/{id}/errors**
- `items[]` · []
- `totalCount` · int

**GET /api/subscriptions/{id}/sessions/period-usage**
- `items[]` · []
- `items[].averageSessionDurationInSeconds` · int
- `items[].lastSessionOccurredAt` · string
- `items[].sessionsCount` · int
- `items[].totalDownloadedBytes` · int
- `items[].totalUploadedBytes` · int
- `totalCount` · int

**GET /api/subscriptions/{id}/sessions/total-usage**
- `model.currentServiceCycleUsage.remainingInBytes` · null
- `model.currentServiceCycleUsage.totalQuotaInBytes` · null
- `model.currentServiceCycleUsage.usedInBytes` · null
- `model.totalDownloadedBytes` · int
- `model.totalNumberOfSessions` · int
- `model.totalUploadedBytes` · int

**GET /api/support/tickets**
- `items[]` · []
- `items[].attachmentsCount` · int
- `items[].commentsCount` · int
- `items[].createdAt` · string
- `items[].customer.displayValue` · string
- `items[].customer.id` · string
- `items[].displayId` · string
- `items[].partner.displayValue` · string
- `items[].partner.id` · string
- `items[].self.displayValue` · string
- `items[].self.id` · string
- `items[].status` · string
- `items[].summary` · string
- `items[].updatedAt` · string
- `items[].zone.displayValue` · string
- `items[].zone.id` · string
- `totalCount` · int

**GET /api/support/tickets/statuses**
- `items[]` · []
- `items[].displayValue` · string
- `items[].id` · string
- `totalCount` · int

**GET /api/tasks/summary**
- `model.totalCompleted` · int
- `model.totalCount` · int
- `model.totalDueInNextSevenDays` · int
- `model.totalDueThisWeek` · int
- `model.totalDueToday` · int
- `model.totalOpen` · int

**GET /api/tasks/types**
- `items[]` · []
- `items[].displayValue` · string
- `items[].id` · string
- `totalCount` · int

**GET /api/transactions**
- `items[]` · []
- `items[].changeType` · null
- `items[].createdBy` · string
- `items[].customer.displayValue` · string
- `items[].customer.id` · string
- `items[].deviceUsername` · string
- `items[].discountAmount` · num
- `items[].discountType` · string
- `items[].id` · int
- `items[].lineOfBusiness.displayValue` · string
- `items[].lineOfBusiness.id` · int
- `items[].occuredAt` · string
- `items[].partner.displayValue` · string
- `items[].partner.id` · string
- `items[].paymentMethod.displayValue` · string
- `items[].paymentMethod.id` · int
- `items[].paymentMode` · string
- `items[].planPrice` · int
- `items[].remainingBalance.currency` · string
- `items[].remainingBalance.value` · num
- `items[].salesType.displayValue` · string
- `items[].salesType.id` · int
- `items[].serialNumber` · string
- `items[].subscription.displayValue` · string
- `items[].subscription.endsAt` · string
- `items[].subscription.id` · string
- `items[].subscription.startsAt` · string
- `items[].subscription.type` · string
- `items[].transactionAmount.currency` · string
- `items[].transactionAmount.value` · num
- `items[].type` · string
- `items[].walletOwnerType.displayValue` · string
- `items[].walletOwnerType.id` · int
- `items[].walletTransferDetails` · null
- `items[].walletType.displayValue` · string
- `items[].walletType.id` · int
- `items[].zoneId` · string
- `totalCount` · int

**GET /api/transactions/payment-methods**
- `items[]` · []
- `items[].paymentMethod.displayValue` · string
- `items[].paymentMethod.id` · int
- `items[].subscriptionId` · string
- `totalCount` · int

**GET /api/transactions/revenue**
- `items[]` · []
- `items[].customer.displayValue` · string
- `items[].customer.id` · string
- `items[].deviceUsername` · string
- `items[].discountAmount` · num
- `items[].discountType` · null
- `items[].id` · int
- `items[].lineOfBusiness.displayValue` · string
- `items[].lineOfBusiness.id` · int
- `items[].occuredAt` · string
- `items[].partner.displayValue` · string
- `items[].partner.id` · string
- `items[].paymentMethod.displayValue` · string
- `items[].paymentMethod.id` · int
- `items[].paymentMode` · string
- `items[].remainingBalance.currency` · string
- `items[].remainingBalance.value` · num
- `items[].salesGroup.displayValue` · string
- `items[].salesGroup.id` · int
- `items[].serialNumber` · string
- `items[].subscription.displayValue` · string
- `items[].subscription.endsAt` · string
- `items[].subscription.id` · string
- `items[].subscription.startsAt` · string
- `items[].subscription.type` · null
- `items[].transactionAmount.currency` · string
- `items[].transactionAmount.value` · num
- `items[].type` · string
- `items[].walletOwnerType.displayValue` · string
- `items[].walletOwnerType.id` · int
- `items[].zoneId` · string
- `totalCount` · int

**GET /api/transactions/revenue/statistics**
- `model.totalRevenue.currency` · string
- `model.totalRevenue.value` · num

**POST /api/auth/Contractor/token**
- `access_token` · ***
- `enrolledSecondFactorMethods` · null
- `expires_in` · num
- `refresh_expires_in` · num
- `refresh_token` · ***
- `second_factor_required` · bool
- `token_type` · ***