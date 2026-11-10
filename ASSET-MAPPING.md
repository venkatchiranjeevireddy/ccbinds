# CCB India asset mapping

All current image URLs are temporary Unsplash photography selected to match each section. Replace the value in `src/config/imageManifest.js` with the approved local asset path when final CCB photography is supplied; layouts and aspect ratios are intentionally preserved.

| Manifest key | Page / section | Status | Intended aspect |
|---|---|---|---|
| homepageHero | Home / hero | Temporary | 16:9 |
| aboutHero | About / hero | Temporary | 16:9 |
| contentCreators, influencers, brands, agencies, mediaProfessionals, aspiringCreators | Ecosystem / category cards | Temporary | 4:3 |
| programsHero | Programs / hero | Temporary | 16:9 |
| eventsHero | Events / hero | Temporary | 16:9 |
| membershipHero | Membership / hero | Temporary | 16:9 |
| partnershipsHero | Partnerships / hero | Temporary | 16:9 |
| knowledgeHero | Knowledge Hub / hero | Temporary | 16:9 |
| recognitionHero | Recognition / hero | Temporary | 16:9 |
| leadershipHero | Leadership / hero | Temporary | 16:9 |
| newsHero | News / hero | Temporary | 16:9 |
| contactHero | Contact / hero | Temporary | 16:9 |

## User and editorial media

The public-site image manifest above currently uses temporary Unsplash assets. Dynamic user-uploaded media uses private Cloudflare R2; Supabase `media_assets` records metadata, owner, object key and visibility. Member profile images, Client logos, portfolio assets and Admin editorial/event images should be uploaded through the role-appropriate API. The Member/Client media endpoint checks the Supabase session and database access before issuing short-lived signed URLs. Keep the R2 bucket private and do not place permanent object URLs or credentials in page data. Public visibility is an explicit metadata decision; the bytes are still served through authorized short-lived access.
