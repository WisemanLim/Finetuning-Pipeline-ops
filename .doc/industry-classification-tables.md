# 산업 도메인 분류 — KSIC / ISIC / NACE / NAICS 통합 표

> 본 자료는 `Perplexity-ISIC,KSIC,NACE,NAICS 분류 조사 및 정리.md`를
> Wise Fine-tuning Pipeline 설계용 레퍼런스 표로 재구성한 것입니다.
> 정본은 통계청 통계분류포털 / UN Statistics Division / Eurostat / US Census를
> 참조하세요.

---

## 0. 용어 — 업태 / 업종 / 종목

| 레벨 | 의미 | KSIC 대응 | 예시 |
|------|------|-----------|------|
| **업태** | "어떤 방식의 사업을 영위하느냐" | 대분류 (A~U, Section) | 제조업, 도매·소매업, 정보통신업 |
| **업종** | "무엇을 하는 사업이냐" (업태 + 세분 활동) | 중·소·세분류 (Division~Class) | 식료품 제조업, 음식점업 |
| **종목** | "무엇을 판매/제공하느냐" (실제 아이템) | 세세분류 (5자리) | 한식 음식점, 빵류 제조, 반도체 메모리 제조 |

행정·세무·통계는 KSIC을 정본으로 사용하며, 국세청 업종코드도 KSIC 기반 확장.

---

## 1. 4 체계 개요 비교

| 항목 | ISIC | KSIC | NACE | NAICS |
|------|------|------|------|-------|
| 정식 명칭 | International Standard Industrial Classification | 한국표준산업분류 | Nomenclature statistique des activités économiques (EU) | North American Industry Classification System |
| 제정 기관 | UN Statistics Division | 통계청 (KOSTAT) | Eurostat | US Census Bureau (미국·캐나다·멕시코 공동) |
| 최신 버전 | Rev.4 (2008+) | 10차 (2017) / 11차 | Rev.2 | 2022 |
| 코드 체계 | Section(A~U) → Div(2) → Group(3) → Class(4) | 대분류(A~U) → 중(2) → 소(3) → 세(4) → 세세(5) | Section(A~U) → Div(2) → Group(3) → Class(4) | Sector(2) → Subsector(3) → Industry group(4) → Industry(5) → National(6) |
| 대분류 수 | 21 | 21 | 21 | ~20 (2자리 Sector) |
| KSIC 대비 관계 | KSIC 상위 참조 (KSIC가 ISIC를 기초로 작성) | — | ISIC와 거의 1:1 (EU 일부 세분화) | 별도 체계, ISIC↔NAICS 크로스워크 존재 |

---

## 2. 대분류(Section) 4 체계 통합 매트릭스 — 21 섹션

| KSIC | KSIC 명칭 | ISIC Rev.4 | NACE Rev.2 | NAICS Sector | NAICS 명칭 |
|:---:|---|:---:|:---:|:---:|---|
| A | 농업·임업·어업 | A | A | 11 | Agriculture, forestry, fishing and hunting |
| B | 광업 | B | B | 21 | Mining, quarrying, and oil & gas extraction |
| C | 제조업 | C | C | 31–33 | Manufacturing |
| D | 전기·가스·증기·공기조절 공급업 | D | D | 22 | Utilities |
| E | 수도·하수·폐기물·환경복원업 | E | E | 22 일부 + 562 | Waste / 일부 Services 분산 |
| F | 건설업 | F | F | 23 | Construction |
| G | 도매 및 소매업 | G | G | 42 / 44–45 | Wholesale trade / Retail trade |
| H | 운수 및 창고업 | H | H | 48–49 | Transportation and warehousing |
| I | 숙박 및 음식점업 | I | I | 72 | Accommodation and food services |
| J | 정보통신업 | J | J | 51 (+ 5182) | Information |
| K | 금융 및 보험업 | K | K | 52 | Finance and insurance |
| L | 부동산업 | L | L | 53 일부 | Real estate (rental/leasing 별도) |
| M | 전문·과학·기술 서비스업 | M | M | 54 | Professional, scientific, technical services |
| N | 사업시설관리·사업지원·임대 서비스업 | N | N | 56 | Administrative and support services |
| O | 공공행정·국방·사회보장 행정 | O | O | 92 | Public administration |
| P | 교육 서비스업 | P | P | 61 | Educational services |
| Q | 보건업 및 사회복지 서비스업 | Q | Q | 62 | Health care and social assistance |
| R | 예술·스포츠·여가 관련 서비스업 | R | R | 71 | Arts, entertainment, recreation |
| S | 협회·단체·수리·기타 개인 서비스업 | S | S | 81 (+ 8113 등) | Other services |
| T | 가구 내 고용활동 | T | T | 814 일부 | Private households |
| U | 국제 및 외국기관 | U | U | (별도 분류) | Extraterritorial organizations |

ISIC / NACE / KSIC는 A~U 알파벳을 그대로 공유. NAICS만 2자리 숫자 Sector 체계.

---

## 3. KSIC 중분류(Division, 2자리) 전체 목록

### A. 농업·임업·어업
| 코드 | 명칭 |
|:---:|---|
| 01 | 작물 및 축산업 |
| 02 | 임업 |
| 03 | 어업 및 양식업 |

### B. 광업
| 코드 | 명칭 |
|:---:|---|
| 05 | 석탄 및 갈탄 채굴업 |
| 06 | 원유 및 천연가스 채굴업 |
| 07 | 금속 광업 |
| 08 | 비금속 광물 광업 |
| 09 | 광업 지원 서비스업 |

### C. 제조업 (10–34, 25개 중분류)
| 코드 | 명칭 |
|:---:|---|
| 10 | 식료품 제조업 |
| 11 | 음료 제조업 |
| 12 | 담배 제조업 |
| 13 | 섬유제품 제조업 (의복 제외) |
| 14 | 의복·의복 액세서리 및 모피 제품 제조업 |
| 15 | 가죽·가방 및 유사 제품 제조업 |
| 16 | 목재 및 나무제품 제조업 (가구 제외) |
| 17 | 펄프·종이 및 종이제품 제조업 |
| 18 | 인쇄 및 기록매체 복제업 |
| 19 | 코크스·연탄 및 석유정제품 제조업 |
| 20 | 화학물질 및 화학제품 제조업 |
| 21 | 의약품 제조업 |
| 22 | 고무 및 플라스틱제품 제조업 |
| 23 | 비금속 광물제품 제조업 |
| 24 | 1차 금속 제조업 |
| 25 | 금속가공제품 제조업 (기계 및 가구 제외) |
| 26 | 전자부품·컴퓨터·영상·음향 및 통신장비 제조업 |
| 27 | 의료·정밀·광학기기 및 시계 제조업 |
| 28 | 전기장비 제조업 |
| 29 | 기타 기계 및 장비 제조업 |
| 30 | 자동차 및 트레일러 제조업 |
| 31 | 기타 운송장비 제조업 |
| 32 | 가구 제조업 |
| 33 | 기타 제품 제조업 |
| 34 | 산업용 기계·장비 수리 및 설치업 |

### D. 전기·가스·증기·공기조절 공급업
| 코드 | 명칭 |
|:---:|---|
| 35 | 전기·가스·증기 및 공기조절 공급업 |

### E. 수도·하수·폐기물·환경복원업
| 코드 | 명칭 |
|:---:|---|
| 36 | 수도업 |
| 37 | 하수 처리업 |
| 38 | 폐기물 수집·운반·처리 및 원료 재생업 |
| 39 | 환경복원업 |

### F. 건설업
| 코드 | 명칭 |
|:---:|---|
| 41 | 건물 건설업 |
| 42 | 토목 건설업 |
| 43 | 전문직별 공사업 |

### G. 도매 및 소매업
| 코드 | 명칭 |
|:---:|---|
| 45 | 자동차 및 자동차부품 판매업 |
| 46 | 도매 및 상품 중개업 |
| 47 | 소매업 (자동차 제외 — 오프라인·온라인 포함) |

### H. 운수 및 창고업
| 코드 | 명칭 |
|:---:|---|
| 49 | 육상 운송 및 파이프라인 운송업 |
| 50 | 수상 운송업 |
| 51 | 항공 운송업 |
| 52 | 창고 및 운송 관련 서비스업 |
| 53 | 우편 및 택배업 |

### I. 숙박 및 음식점업
| 코드 | 명칭 |
|:---:|---|
| 55 | 숙박업 |
| 56 | 음식점 및 주점업 |

### J. 정보통신업
| 코드 | 명칭 |
|:---:|---|
| 58 | 출판업 |
| 59 | 영상·오디오 기록물 제작 및 배급업 |
| 60 | 방송업 |
| 61 | 우편 제외 통신업 (유선·무선 통신 등) |
| 62 | 컴퓨터 프로그래밍·시스템 통합 및 관리업 |
| 63 | 정보 서비스업 (포털, 데이터 처리 등) |

### K. 금융 및 보험업
| 코드 | 명칭 |
|:---:|---|
| 64 | 금융업 (중앙은행, 예금·대출, 기타 금융 중개) |
| 65 | 보험 및 연금업 |
| 66 | 금융 및 보험 관련 서비스업 |

### L. 부동산업
| 코드 | 명칭 |
|:---:|---|
| 68 | 부동산업 (임대·매매·중개 및 관련 서비스) |

### M. 전문·과학 및 기술 서비스업
| 코드 | 명칭 |
|:---:|---|
| 69 | 법무·회계 및 세무 관련 서비스업 |
| 70 | 본사 및 경영 컨설팅 서비스업 |
| 71 | 건축·엔지니어링 및 관련 기술 서비스업 |
| 72 | 연구개발업 (R&D) |
| 73 | 광고업 및 시장조사 |
| 74 | 기타 전문·과학·기술 서비스업 (전문 디자인, 사진 등) |

### N. 사업시설관리·사업지원·임대 서비스업
| 코드 | 명칭 |
|:---:|---|
| 77 | 임대업 (지식재산권 제외, 비부동산 임대) |
| 78 | 고용알선 및 인력공급업 |
| 79 | 여행사 및 예약 서비스업 |
| 80 | 보안 및 경비 서비스업 |
| 81 | 건물·조경 및 기타 사업 지원 서비스업 |

### O. 공공행정·국방·사회보장 행정
| 코드 | 명칭 |
|:---:|---|
| 84 | 공공행정·국방·사회보장 행정 |

### P. 교육 서비스업
| 코드 | 명칭 |
|:---:|---|
| 85 | 교육 서비스업 (학교, 교육기관, 학원 등) |

### Q. 보건업 및 사회복지 서비스업
| 코드 | 명칭 |
|:---:|---|
| 86 | 보건업 (병원, 의원, 치과, 한방, 검진 등) |
| 87 | Residential형 사회복지 서비스업 (입소·시설 중심) |
| 88 | Non-residential 사회복지 서비스업 (비거주형 복지) |

### R. 예술·스포츠 및 여가관련 서비스업
| 코드 | 명칭 |
|:---:|---|
| 90 | 창작·예술 및 여가 관련 서비스업 |
| 91 | 도서관·기록물 보존 및 기타 문화관련 서비스업 |
| 92 | 스포츠 및 오락 관련 서비스업 |

### S. 협회·단체·수리·기타 개인 서비스업
| 코드 | 명칭 |
|:---:|---|
| 94 | 협회 및 단체 |
| 95 | 개인 및 가정용품 수리업 |
| 96 | 기타 개인 서비스업 (세탁, 미용 등) |

### T. 가구 내 고용활동
| 코드 | 명칭 |
|:---:|---|
| 97 | 가구 내 고용활동 |
| 98 | 가구의 자가소비를 위한 상품 및 서비스 생산활동 |

### U. 국제 및 외국기관
| 코드 | 명칭 |
|:---:|---|
| 99 | 국제 및 외국기관 |

---

## 4. 제조업(C) 중분류 4 체계 매핑

| 기능 범위 | ISIC Rev.4 Div | KSIC Div | NACE Rev.2 Div | NAICS Subsector |
|---|:---:|:---:|:---:|:---|
| 식료품 | 10 | 10 | 10 | 311 Food mfg |
| 음료 | 11 | 11 | 11 | 312 Beverage & tobacco (음료+담배 묶음) |
| 담배 | 12 | 12 | 12 | 312 일부 |
| 섬유 | 13 | 13 | 13 | 313–314 Textile mills / Textile product mills |
| 의복 | 14 | 14 | 14 | 315 Apparel mfg |
| 가죽·가방 | 15 | 15 | 15 | 316 Leather and allied product mfg |
| 목재·목제품 | 16 | 16 | 16 | 321 Wood product mfg |
| 펄프·종이 | 17 | 17 | 17 | 322 Paper mfg |
| 인쇄·기록매체 | 18 | 18 | 18 | 323 Printing |
| 코크스·석유정제 | 19 | 19 | 19 | 324 Petroleum & coal products mfg |
| 화학제품 | 20 | 20 | 20 | 325 Chemical mfg |
| 의약품 | 21 | 21 | 21 | 3254 Pharmaceutical and medicine mfg |
| 고무·플라스틱 | 22 | 22 | 22 | 326 Plastics and rubber products mfg |
| 비금속 광물제품 | 23 | 23 | 23 | 327 Nonmetallic mineral product mfg |
| 1차 금속 | 24 | 24 | 24 | 331 Primary metal mfg |
| 금속가공제품 | 25 | 25 | 25 | 332 Fabricated metal product mfg |
| 전자·컴퓨터·광학 | 26 | 26 | 26 | 334 Computer & electronic product mfg |
| 의료·정밀·광학기기 | (26 일부) | 27 | (26 일부) | 3345 Measuring/medical instruments |
| 전기장비 | 27 | 28 | 27 | 335 Electrical equipment, appliance mfg |
| 기타 기계·장비 | 28 | 29 | 28 | 333 Machinery mfg |
| 자동차·트레일러 | 29 | 30 | 29 | 3361–3363 Motor vehicle mfg |
| 기타 운송장비 | 30 | 31 | 30 | 3364–3369 Other transportation equipment |
| 가구 | 31 | 32 | 31 | 337 Furniture and related |
| 기타 제품 | 32 | 33 | 32 | 339 Miscellaneous mfg |
| 수리 및 설치 | 33 | 34 | 33 | 8113 (NAICS는 서비스 섹터로 분리) |

> **KSIC 특이점**: ISIC의 26번(컴퓨터/전자/광학)을 KSIC는 26(전자·컴퓨터·통신장비)과 27(의료·정밀·광학기기)로 분리. 그리고 KSIC는 추가로 34번 (산업용 기계·장비 수리·설치업)을 둠.

---

## 5. 정보통신업(J) 중분류 4 체계 매핑

| 기능 범위 | ISIC Rev.4 Div | KSIC Div | NACE Rev.2 Div | NAICS 예시 |
|---|:---:|:---:|:---:|:---|
| 출판 | 58 | 58 | 58 | 5111 Newspaper, periodical, book publishers |
| 영상·오디오·음악 제작 | 59 | 59 | 59 | 512 Motion picture & sound recording |
| 방송 | 60 | 60 | 60 | 515 Broadcasting |
| 통신 (우편 제외) | 61 | 61 | 61 | 517 Telecommunications |
| 컴퓨터 프로그래밍·SI | 62 | 62 | 62 | 5415 Computer systems design, 5182 Data hosting |
| 정보 서비스 (포털·데이터 처리) | 63 | 63 | 63 | 519 Other information services, 5182 |

---

## 6. 보건업 및 사회복지(Q) 중분류 4 체계 매핑

| 기능 범위 | ISIC Rev.4 Div | KSIC Div | NACE Rev.2 Div | NAICS 예시 |
|---|:---:|:---:|:---:|:---|
| 의료 (병원·의원·치과·검진) | 86 | 86 | 86 | 621 Ambulatory health care, 622 Hospitals |
| 입소형 사회복지 (요양시설 등) | 87 | 87 | 87 | 623 Nursing and residential care facilities |
| 비거주형 사회복지 | 88 | 88 | 88 | 624 Social assistance |

---

## 7. WFP 파이프라인 카테고리 프리셋 매핑 (요약)

PRD §3.2 기준 — 추천 LLM·데이터 소스·전략과 KSIC 대분류 연결.

| KSIC | 카테고리 명칭 | 추천 베이스 모델 | 권장 학습 전략 |
|:---:|---|---|---|
| C | 제조업 | Qwen2-7B-Instruct, Mistral-7B-Instruct | QLoRA + 도메인 어댑터 |
| G | 도매·소매업 | Llama-3-8B-Instruct, Qwen2-7B | QLoRA + Instruction 튜닝 |
| I | 숙박·음식점업 | Gemma-2-9B-it, Phi-3-medium | QLoRA + 톤·매너 튜닝 |
| J | 정보통신업 | CodeLlama-13B, DeepSeek-Coder-6.7B, Qwen2.5-Coder | QLoRA + Code-specific |
| K | 금융·보험업 | Llama-3-8B-Instruct, Qwen2-14B | LoRA + 안전성 평가 강화 |
| M | 전문·과학·기술 서비스 | Llama-3-8B-Instruct, Mistral-7B | LoRA + 긴 컨텍스트 |
| P | 교육 | Gemma-2-9B-it, Llama-3-8B | QLoRA + 난이도 조절 |
| Q | 보건업·사회복지 | Llama-3-8B-Instruct, BioMistral, Meditron | QLoRA + 안전성·근거성 평가 |
| F | 건설업 | Mistral-7B-Instruct, Qwen2-7B | QLoRA |
| 기타 (A,B,D,E,H,L,N,O,R,S,T,U) | 기본 프리셋 | Llama-3-8B-Instruct | QLoRA |

WFP 코드 위치:
- `ml-frontend/lib/ksic.ts` — KSIC 21개 대분류 + 카드 UI 메타데이터
- `ml-worker/src/wfp_worker/stage4_model/model_catalog.py` — 추천 모델 시드 데이터
- `ml-worker/src/wfp_worker/api/models_api.py` — 카탈로그 API (DB → 시드 폴백)

---

## 8. 데이터 모델 권장 구조 (참고)

```sql
-- 산업 분류 코드 정본
industry_classification (
  id           uuid PK,
  system       enum('ISIC','KSIC','NACE','NAICS'),
  level        enum('section','division','group','class','subclass'),
  code         varchar(8),
  ko_name      text,
  en_name      text,
  parent_id    uuid FK,
  UNIQUE(system, code)
)

-- 4 체계 간 매핑 (KSIC을 internal canonical로)
industry_code_mapping (
  id              uuid PK,
  ksic_division   varchar(4) NOT NULL,
  isic_division   varchar(4),
  nace_division   varchar(4),
  naics_code      varchar(8),
  relation_type   enum('exact','broader','narrower','related'),
  notes           text
)
```

---

## 9. 정본 데이터 소스

| 체계 | 정본 출처 |
|------|-----------|
| **KSIC** | 통계청 통계분류포털 — 한국표준산업분류 (10/11차) XLSX |
| **ISIC** | UN Statistics Division — ISIC Rev.4 Structure |
| **NACE** | Eurostat — NACE Rev.2 Structure and explanatory notes |
| **NAICS** | US Census Bureau — NAICS 2022 Manual & XLS |
| 통합 연계표 | 통계분류포털 "통합경제분류연계표" (ISIC–KSIC–KCPC) |
| 국세청 업종코드 | 홈택스 "업종코드–표준산업분류 연계표" XLS |
| 오픈소스 | github.com/FinanceData/KSIC (CSV, KSIC 9차) |
