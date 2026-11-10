export type FieldType = 'text' | 'textarea' | 'number' | 'date' | 'datetime' | 'boolean' | 'select' | 'json'

export type AdminField = {
  key: string
  label: string
  type: FieldType
  options?: string[]
  required?: boolean
  placeholder?: string
}

export type AdminResource = {
  key: string
  label: string
  description: string
  table: string
  idKey: string
  select: string
  orderBy?: string
  columns: { key: string; label: string }[]
  fields: AdminField[]
  create: boolean
  remove: boolean
  search: string
}

export const resources: AdminResource[] = [
  {
    key: 'members', label: 'Members', description: 'Review Member profiles and visibility.',
    table: 'member_profiles', idKey: 'user_id',
    select: 'user_id,headline,location,availability,is_public,verified_at,profile_media_id,created_at,user_profiles(display_name,created_at)',
    columns: [
      { key: 'user_profiles.display_name', label: 'Member' }, { key: 'headline', label: 'Headline' },
      { key: 'location', label: 'Location' }, { key: 'availability', label: 'Availability' },
      { key: 'is_public', label: 'Profile public' }, { key: 'created_at', label: 'Joined' },
    ],
    fields: [
      { key: 'headline', label: 'Professional headline', type: 'text' },
      { key: 'location', label: 'Location', type: 'text' },
      { key: 'availability', label: 'Availability', type: 'select', options: ['available', 'limited', 'unavailable'] },
      { key: 'is_public', label: 'Public profile', type: 'boolean' },
      { key: 'profile_media_id', label: 'Profile image media ID', type: 'text' },
      { key: 'verified_at', label: 'Verified at', type: 'datetime' },
    ], create: false, remove: false, search: 'headline',
  },
  {
    key: 'clients', label: 'Clients', description: 'Review Client organisations and verification.',
    table: 'client_profiles', idKey: 'user_id',
    select: 'user_id,company_name,organization_type,industry,location,verification_status,verified_at,logo_media_id,created_at,user_profiles(display_name)',
    columns: [
      { key: 'company_name', label: 'Organisation' }, { key: 'user_profiles.display_name', label: 'Account' },
      { key: 'industry', label: 'Industry' }, { key: 'location', label: 'Location' },
      { key: 'verification_status', label: 'Verification' }, { key: 'created_at', label: 'Created' },
    ],
    fields: [
      { key: 'company_name', label: 'Organisation name', type: 'text', required: true },
      { key: 'organization_type', label: 'Organisation type', type: 'text' },
      { key: 'industry', label: 'Industry', type: 'text' }, { key: 'location', label: 'Location', type: 'text' },
      { key: 'verification_status', label: 'Verification status', type: 'select', options: ['unverified', 'pending', 'verified', 'rejected'] },
      { key: 'logo_media_id', label: 'Logo media ID', type: 'text' },
      { key: 'verified_at', label: 'Verified at', type: 'datetime' },
    ], create: false, remove: false, search: 'company_name',
  },
  {
    key: 'events', label: 'Events', description: 'Create and publish events, registration details, and dates.',
    table: 'events', idKey: 'id',
    select: 'id,title,slug,summary,status,starts_at,ends_at,timezone,venue_name,venue_address,is_online,registration_closes_at,program_id,featured_media_id,event_category,target_audience,event_visibility,external_rsvp_url,rsvp_closed,announcement_audience,created_at',
    columns: [{ key: 'title', label: 'Event' }, { key: 'status', label: 'Status' }, { key: 'starts_at', label: 'Starts' }, { key: 'venue_name', label: 'Venue' }, { key: 'is_online', label: 'Online' }],
    fields: [
      { key: 'title', label: 'Event title', type: 'text', required: true }, { key: 'slug', label: 'URL slug', type: 'text', required: true },
      { key: 'summary', label: 'Summary', type: 'textarea' }, { key: 'description', label: 'Description', type: 'textarea' },
      { key: 'status', label: 'Status', type: 'select', options: ['draft', 'published', 'cancelled', 'completed'] },
      { key: 'program_id', label: 'Programme ID (optional)', type: 'text' }, { key: 'featured_media_id', label: 'Featured image media ID (from Media library)', type: 'text' },
      { key: 'event_category', label: 'Event category', type: 'text' },
      { key: 'target_audience', label: 'Target audience (JSON array: members, clients, both)', type: 'json', placeholder: '["members","clients"]' },
      { key: 'event_visibility', label: 'Event visibility', type: 'select', options: ['public', 'unlisted', 'private'], required: true },
      { key: 'external_rsvp_url', label: 'External RSVP URL (HTTPS)', type: 'text', placeholder: 'https://forms.gle/...' },
      { key: 'rsvp_closed', label: 'Close RSVP button', type: 'boolean' },
      { key: 'announcement_audience', label: 'Announcement audience (JSON array: members, clients)', type: 'json', placeholder: '["members"]' },
      { key: 'starts_at', label: 'Starts at', type: 'datetime' }, { key: 'ends_at', label: 'Ends at', type: 'datetime' },
      { key: 'timezone', label: 'Timezone', type: 'text', placeholder: 'Asia/Kolkata' },
      { key: 'venue_name', label: 'Venue name', type: 'text' }, { key: 'venue_address', label: 'Venue address', type: 'textarea' },
      { key: 'is_online', label: 'Online event', type: 'boolean' },
      { key: 'registration_closes_at', label: 'RSVP deadline', type: 'datetime' },
    ], create: true, remove: true, search: 'title',
  },
  {
    key: 'event_media', label: 'Event gallery media', description: 'Attach public images and video from the private R2 media library to Events by media ID.',
    table: 'event_media', idKey: 'id', select: 'id,event_id,media_asset_id,sort_order', orderBy: 'event_id',
    columns: [{ key: 'event_id', label: 'Event ID' }, { key: 'media_asset_id', label: 'Media ID' }, { key: 'sort_order', label: 'Order' }],
    fields: [{ key: 'event_id', label: 'Event ID', type: 'text', required: true }, { key: 'media_asset_id', label: 'Media asset ID', type: 'text', required: true }, { key: 'sort_order', label: 'Display order', type: 'number' }], create: true, remove: true, search: '',
  },
  {
    key: 'programs', label: 'Programs', description: 'Manage ongoing initiatives and programme pages.',
    table: 'programs', idKey: 'id', select: 'id,title,slug,summary,description,status,starts_on,ends_on,featured_media_id,created_at',
    columns: [{ key: 'title', label: 'Programme' }, { key: 'status', label: 'Status' }, { key: 'starts_on', label: 'Starts' }, { key: 'ends_on', label: 'Ends' }],
    fields: [
      { key: 'title', label: 'Programme title', type: 'text', required: true }, { key: 'slug', label: 'URL slug', type: 'text', required: true },
      { key: 'featured_media_id', label: 'Featured image media ID (from Media library)', type: 'text' },
      { key: 'summary', label: 'Summary', type: 'textarea' }, { key: 'description', label: 'Description', type: 'textarea' },
      { key: 'status', label: 'Status', type: 'select', options: ['draft', 'published', 'archived'] },
      { key: 'starts_on', label: 'Starts on', type: 'date' }, { key: 'ends_on', label: 'Ends on', type: 'date' },
    ], create: true, remove: true, search: 'title',
  },
  {
    key: 'articles', label: 'Content', description: 'Write and publish announcements, insights, and reports.',
    table: 'articles', idKey: 'id', select: 'id,title,slug,excerpt,body,content_type,status,featured_media_id,published_at,created_at',
    columns: [{ key: 'title', label: 'Title' }, { key: 'content_type', label: 'Type' }, { key: 'status', label: 'Status' }, { key: 'published_at', label: 'Published' }],
    fields: [
      { key: 'title', label: 'Title', type: 'text', required: true }, { key: 'slug', label: 'URL slug', type: 'text', required: true },
      { key: 'excerpt', label: 'Excerpt', type: 'textarea' }, { key: 'body', label: 'Article body', type: 'textarea', required: true },
      { key: 'content_type', label: 'Content type', type: 'select', options: ['news', 'insight', 'research', 'report', 'announcement'] },
      { key: 'featured_media_id', label: 'Featured media ID (optional)', type: 'text' },
      { key: 'status', label: 'Status', type: 'select', options: ['draft', 'published', 'archived'] },
      { key: 'published_at', label: 'Published at', type: 'datetime' },
    ], create: true, remove: true, search: 'title',
  },
  {
    key: 'professional_categories', label: 'Professional categories', description: 'Maintain the shared Member and Client taxonomy.',
    table: 'professional_categories', idKey: 'id', select: 'id,name,slug,description,is_active,sort_order,created_at',
    columns: [{ key: 'name', label: 'Category' }, { key: 'slug', label: 'Slug' }, { key: 'is_active', label: 'Active' }, { key: 'sort_order', label: 'Order' }],
    fields: [
      { key: 'name', label: 'Name', type: 'text', required: true }, { key: 'slug', label: 'Slug', type: 'text', required: true },
      { key: 'description', label: 'Description', type: 'textarea' }, { key: 'is_active', label: 'Active', type: 'boolean' }, { key: 'sort_order', label: 'Display order', type: 'number' },
    ], create: true, remove: true, search: 'name',
  },
  {
    key: 'skills', label: 'Skills', description: 'Manage skills used by Member profiles and discovery.',
    table: 'skills', idKey: 'id', select: 'id,name,slug,description,is_active,created_at',
    columns: [{ key: 'name', label: 'Skill' }, { key: 'slug', label: 'Slug' }, { key: 'is_active', label: 'Active' }],
    fields: [
      { key: 'name', label: 'Name', type: 'text', required: true }, { key: 'slug', label: 'Slug', type: 'text', required: true },
      { key: 'description', label: 'Description', type: 'textarea' }, { key: 'is_active', label: 'Active', type: 'boolean' },
    ], create: true, remove: true, search: 'name',
  },
  {
    key: 'professional_roles', label: 'Professional roles', description: 'Manage approved professional roles and services.',
    table: 'professional_roles', idKey: 'id', select: 'id,name,slug,description,is_active,created_at',
    columns: [{ key: 'name', label: 'Role or service' }, { key: 'slug', label: 'Slug' }, { key: 'is_active', label: 'Active' }],
    fields: [{ key: 'name', label: 'Name', type: 'text', required: true }, { key: 'slug', label: 'Slug', type: 'text', required: true }, { key: 'description', label: 'Description', type: 'textarea' }, { key: 'is_active', label: 'Active', type: 'boolean' }], create: true, remove: true, search: 'name',
  },
  {
    key: 'professional_tools', label: 'Tools and software', description: 'Manage approved tools and software expertise.',
    table: 'professional_tools', idKey: 'id', select: 'id,name,slug,description,is_active,created_at',
    columns: [{ key: 'name', label: 'Tool' }, { key: 'slug', label: 'Slug' }, { key: 'is_active', label: 'Active' }],
    fields: [{ key: 'name', label: 'Name', type: 'text', required: true }, { key: 'slug', label: 'Slug', type: 'text', required: true }, { key: 'description', label: 'Description', type: 'textarea' }, { key: 'is_active', label: 'Active', type: 'boolean' }], create: true, remove: true, search: 'name',
  },
  {
    key: 'taxonomy_aliases', label: 'Taxonomy aliases', description: 'Manage searchable aliases for existing roles, skills and tools.',
    table: 'taxonomy_aliases', idKey: 'id', select: 'id,alias,role_id,skill_id,tool_id,created_at',
    columns: [{ key: 'alias', label: 'Alias or keyword' }, { key: 'role_id', label: 'Role ID' }, { key: 'skill_id', label: 'Skill ID' }, { key: 'tool_id', label: 'Tool ID' }],
    fields: [{ key: 'alias', label: 'Alias or keyword', type: 'text', required: true }, { key: 'role_id', label: 'Role ID (one target only)', type: 'text' }, { key: 'skill_id', label: 'Skill ID', type: 'text' }, { key: 'tool_id', label: 'Tool ID', type: 'text' }], create: true, remove: true, search: 'alias',
  },
  {
    key: 'taxonomy_suggestions', label: 'Taxonomy suggestions', description: 'Review suggestions submitted by Members and Clients.',
    table: 'taxonomy_suggestions', idKey: 'id', select: 'id,suggestion_type,name,description,status,admin_notes,submitted_at,reviewed_at', orderBy: 'submitted_at',
    columns: [{ key: 'suggestion_type', label: 'Type' }, { key: 'name', label: 'Suggestion' }, { key: 'status', label: 'Status' }, { key: 'submitted_at', label: 'Received' }],
    fields: [{ key: 'status', label: 'Review status', type: 'select', options: ['submitted', 'under_review', 'approved', 'rejected'] }, { key: 'admin_notes', label: 'Admin notes', type: 'textarea' }, { key: 'reviewed_at', label: 'Reviewed at', type: 'datetime' }], create: false, remove: false, search: 'name',
  },
  {
    key: 'admin_taxonomy_usage', label: 'Taxonomy analytics', description: 'Review how many Member profiles and opportunities use each approved taxonomy entry.',
    table: 'admin_taxonomy_usage', idKey: 'id', select: 'id,taxonomy_type,taxonomy_id,name,is_active,member_count,opportunity_count', orderBy: 'name',
    columns: [{ key: 'taxonomy_type', label: 'Type' }, { key: 'name', label: 'Option' }, { key: 'member_count', label: 'Member profiles' }, { key: 'opportunity_count', label: 'Opportunities' }, { key: 'is_active', label: 'Active' }],
    fields: [], create: false, remove: false, search: 'name',
  },
  {
    key: 'professional_role_categories', label: 'Role categories', description: 'Associate approved roles with professional categories using stable taxonomy IDs.',
    table: 'professional_role_categories', idKey: 'id', select: 'id,role_id,category_id', orderBy: 'role_id',
    columns: [{ key: 'role_id', label: 'Role ID' }, { key: 'category_id', label: 'Category ID' }],
    fields: [{ key: 'role_id', label: 'Role ID', type: 'text', required: true }, { key: 'category_id', label: 'Category ID', type: 'text', required: true }], create: true, remove: true, search: 'role_id',
  },
  {
    key: 'skill_categories', label: 'Skill categories', description: 'Associate approved skills with professional categories.',
    table: 'skill_categories', idKey: 'id', select: 'id,skill_id,category_id', orderBy: 'skill_id',
    columns: [{ key: 'skill_id', label: 'Skill ID' }, { key: 'category_id', label: 'Category ID' }],
    fields: [{ key: 'skill_id', label: 'Skill ID', type: 'text', required: true }, { key: 'category_id', label: 'Category ID', type: 'text', required: true }], create: true, remove: true, search: 'skill_id',
  },
  {
    key: 'professional_tool_categories', label: 'Tool categories', description: 'Associate approved tools and software with categories.',
    table: 'professional_tool_categories', idKey: 'id', select: 'id,tool_id,category_id', orderBy: 'tool_id',
    columns: [{ key: 'tool_id', label: 'Tool ID' }, { key: 'category_id', label: 'Category ID' }],
    fields: [{ key: 'tool_id', label: 'Tool ID', type: 'text', required: true }, { key: 'category_id', label: 'Category ID', type: 'text', required: true }], create: true, remove: true, search: 'tool_id',
  },
  {
    key: 'membership_applications', label: 'Membership applications', description: 'Review submitted applications and add internal notes.',
    table: 'membership_applications', idKey: 'id', select: 'id,full_name,email,phone,organization,requested_category,message,status,admin_notes,submitted_at', orderBy: 'submitted_at',
    columns: [{ key: 'full_name', label: 'Applicant' }, { key: 'email', label: 'Email' }, { key: 'requested_category', label: 'Category' }, { key: 'status', label: 'Status' }, { key: 'submitted_at', label: 'Received' }],
    fields: [
      { key: 'status', label: 'Status', type: 'select', options: ['submitted', 'under_review', 'approved', 'rejected', 'withdrawn'] },
      { key: 'admin_notes', label: 'Internal Admin notes', type: 'textarea' },
    ], create: false, remove: false, search: 'full_name',
  },
  {
    key: 'client_service_requests', label: 'Client service requests', description: 'Track service enquiries submitted by Clients.',
    table: 'client_service_requests', idKey: 'id', select: 'id,request_type,subject,description,status,admin_notes,submitted_at,client_profiles(company_name)', orderBy: 'submitted_at',
    columns: [{ key: 'subject', label: 'Request' }, { key: 'client_profiles.company_name', label: 'Client' }, { key: 'request_type', label: 'Type' }, { key: 'status', label: 'Status' }, { key: 'submitted_at', label: 'Received' }],
    fields: [
      { key: 'status', label: 'Status', type: 'select', options: ['submitted', 'under_review', 'assigned', 'in_progress', 'resolved', 'closed'] },
      { key: 'admin_notes', label: 'Internal Admin notes', type: 'textarea' },
    ], create: false, remove: false, search: 'subject',
  },
  {
    key: 'memberships', label: 'Memberships', description: 'View and manage membership status and dates.',
    table: 'memberships', idKey: 'id', select: 'id,user_id,membership_category,membership_number,status,starts_at,ends_at,created_at',
    columns: [{ key: 'membership_number', label: 'Number' }, { key: 'membership_category', label: 'Category' }, { key: 'status', label: 'Status' }, { key: 'starts_at', label: 'Starts' }, { key: 'ends_at', label: 'Ends' }],
    fields: [
      { key: 'membership_category', label: 'Category', type: 'text', required: true }, { key: 'membership_number', label: 'Membership number', type: 'text' },
      { key: 'status', label: 'Status', type: 'select', options: ['pending', 'active', 'expired', 'suspended', 'cancelled'] },
      { key: 'starts_at', label: 'Starts on', type: 'date' }, { key: 'ends_at', label: 'Ends on', type: 'date' },
    ], create: false, remove: false, search: 'membership_number',
  },
  {
    key: 'recognition_awards', label: 'Awards', description: 'Manage recognition programmes and nomination windows.',
    table: 'recognition_awards', idKey: 'id', select: 'id,title,slug,description,award_year,status,nomination_opens_at,nomination_closes_at,created_at',
    columns: [{ key: 'title', label: 'Award' }, { key: 'award_year', label: 'Year' }, { key: 'status', label: 'Status' }, { key: 'nomination_opens_at', label: 'Nominations open' }],
    fields: [
      { key: 'title', label: 'Award title', type: 'text', required: true }, { key: 'slug', label: 'Slug', type: 'text', required: true },
      { key: 'description', label: 'Description', type: 'textarea' }, { key: 'award_year', label: 'Award year', type: 'number' },
      { key: 'status', label: 'Status', type: 'select', options: ['draft', 'open', 'closed', 'published', 'archived'] },
      { key: 'nomination_opens_at', label: 'Nominations open at', type: 'datetime' }, { key: 'nomination_closes_at', label: 'Nominations close at', type: 'datetime' },
    ], create: true, remove: true, search: 'title',
  },
  {
    key: 'media_assets', label: 'Media library', description: 'Review R2 image metadata linked to profiles, events, and content.',
    table: 'media_assets', idKey: 'id', select: 'id,owner_user_id,bucket_name,object_key,original_filename,mime_type,file_size_bytes,visibility,alt_text,created_at',
    columns: [{ key: 'preview_url', label: 'Preview' }, { key: 'original_filename', label: 'File' }, { key: 'id', label: 'Media ID' }, { key: 'bucket_name', label: 'Bucket' }, { key: 'object_key', label: 'Object key' }, { key: 'mime_type', label: 'Type' }, { key: 'visibility', label: 'Visibility' }],
    fields: [{ key: 'visibility', label: 'Visibility', type: 'select', options: ['public', 'private'] }, { key: 'alt_text', label: 'Alt text', type: 'text' }],
    create: false, remove: false, search: 'original_filename',
  },
  {
    key: 'work_opportunities', label: 'Opportunities', description: 'Moderate client opportunities and their publishing lifecycle.',
    table: 'work_opportunities', idKey: 'id', select: 'id,title,description,status,location,work_arrangement,start_date,deadline,application_deadline,created_at',
    columns: [{ key: 'title', label: 'Opportunity' }, { key: 'status', label: 'Status' }, { key: 'location', label: 'Location' }, { key: 'deadline', label: 'Deadline' }],
    fields: [{ key: 'status', label: 'Status', type: 'select', options: ['draft', 'published', 'applications_closed', 'in_progress', 'completed', 'cancelled'] }],
    create: false, remove: false, search: 'title',
  },
  {
    key: 'applications', label: 'Opportunity applications', description: 'Review applications submitted for client opportunities.',
    table: 'applications', idKey: 'id', select: 'id,opportunity_id,member_id,cover_message,status,client_message,submitted_at,status_updated_at', orderBy: 'submitted_at',
    columns: [{ key: 'opportunity_id', label: 'Opportunity ID' }, { key: 'member_id', label: 'Member ID' }, { key: 'status', label: 'Status' }, { key: 'submitted_at', label: 'Submitted' }],
    fields: [
      { key: 'status', label: 'Status', type: 'select', options: ['submitted', 'under_review', 'shortlisted', 'selected', 'rejected', 'withdrawn'] },
      { key: 'client_message', label: 'Client message', type: 'textarea' },
    ], create: false, remove: false, search: 'cover_message',
  },
  {
    key: 'partnership_enquiries', label: 'Partnership enquiries', description: 'Review partnership requests and assign follow-up status.',
    table: 'partnership_enquiries', idKey: 'id', select: 'id,organization_name,contact_name,contact_email,contact_phone,partnership_type,message,status,admin_notes,submitted_at', orderBy: 'submitted_at',
    columns: [{ key: 'organization_name', label: 'Organisation' }, { key: 'contact_name', label: 'Contact' }, { key: 'partnership_type', label: 'Partnership' }, { key: 'status', label: 'Status' }, { key: 'submitted_at', label: 'Received' }],
    fields: [
      { key: 'status', label: 'Status', type: 'select', options: ['submitted', 'under_review', 'assigned', 'in_progress', 'resolved', 'closed'] },
      { key: 'admin_notes', label: 'Internal Admin notes', type: 'textarea' },
    ], create: false, remove: false, search: 'organization_name',
  },
  {
    key: 'recognition_nominations', label: 'Award nominations', description: 'Review community award nominations and record decisions.',
    table: 'recognition_nominations', idKey: 'id', select: 'id,award_id,nominee_name,nominee_organization,nominator_name,nominator_email,rationale,status,admin_notes,submitted_at', orderBy: 'submitted_at',
    columns: [{ key: 'nominee_name', label: 'Nominee' }, { key: 'nominee_organization', label: 'Organisation' }, { key: 'nominator_name', label: 'Nominated by' }, { key: 'status', label: 'Status' }, { key: 'submitted_at', label: 'Received' }],
    fields: [
      { key: 'status', label: 'Status', type: 'select', options: ['submitted', 'under_review', 'shortlisted', 'selected', 'rejected', 'withdrawn'] },
      { key: 'admin_notes', label: 'Internal Admin notes', type: 'textarea' },
    ], create: false, remove: false, search: 'nominee_name',
  },
  {
    key: 'program_enrollments', label: 'Programme enrollments', description: 'Review people enrolled in ongoing programmes.',
    table: 'program_enrollments', idKey: 'program_id', select: 'program_id,user_id,status,enrolled_at,updated_at', orderBy: 'enrolled_at',
    columns: [{ key: 'program_id', label: 'Programme ID' }, { key: 'user_id', label: 'Member ID' }, { key: 'status', label: 'Status' }, { key: 'enrolled_at', label: 'Enrolled' }],
    fields: [],
    create: false, remove: false, search: '',
  },
  {
    key: 'reviews', label: 'Reviews', description: 'Moderate engagement reviews before publication.',
    table: 'reviews', idKey: 'id', select: 'id,opportunity_id,reviewer_user_id,reviewed_user_id,rating,review_text,status,created_at',
    columns: [{ key: 'rating', label: 'Rating' }, { key: 'review_text', label: 'Review' }, { key: 'status', label: 'Status' }, { key: 'created_at', label: 'Received' }],
    fields: [{ key: 'status', label: 'Moderation status', type: 'select', options: ['pending', 'published', 'hidden', 'rejected'] }],
    create: false, remove: false, search: 'review_text',
  },
  {
    key: 'subscription_plans', label: 'Subscription plans', description: 'Configure Member and Client plan records. Pricing is not pre-filled.',
    table: 'subscription_plans', idKey: 'id', select: 'id,audience,name,description,billing_period,price_amount,currency_code,trial_days,is_active,created_at',
    columns: [{ key: 'name', label: 'Plan' }, { key: 'audience', label: 'Audience' }, { key: 'billing_period', label: 'Billing' }, { key: 'price_amount', label: 'Price' }, { key: 'is_active', label: 'Active' }],
    fields: [
      { key: 'audience', label: 'Audience', type: 'select', options: ['member', 'client'], required: true },
      { key: 'name', label: 'Plan name', type: 'text', required: true }, { key: 'description', label: 'Description', type: 'textarea' },
      { key: 'billing_period', label: 'Billing period', type: 'select', options: ['monthly', 'quarterly', 'yearly', 'one_time'], required: true },
      { key: 'price_amount', label: 'Price amount', type: 'number' }, { key: 'currency_code', label: 'Currency code', type: 'text', placeholder: 'INR' },
      { key: 'trial_days', label: 'Trial days', type: 'number' }, { key: 'is_active', label: 'Active', type: 'boolean' },
    ], create: true, remove: true, search: 'name',
  },
  {
    key: 'subscriptions', label: 'Subscriptions', description: 'Review current trial and subscription status.',
    table: 'subscriptions', idKey: 'id', select: 'id,user_id,plan_id,status,trial_starts_at,trial_ends_at,starts_at,current_period_ends_at,renews_at,cancelled_at,created_at',
    columns: [{ key: 'user_id', label: 'Account ID' }, { key: 'status', label: 'Status' }, { key: 'trial_ends_at', label: 'Trial ends' }, { key: 'current_period_ends_at', label: 'Period ends' }],
    fields: [{ key: 'status', label: 'Status', type: 'select', options: ['trial', 'active', 'past_due', 'expired', 'cancelled', 'suspended'] }],
    create: false, remove: false, search: 'status',
  },
  {
    key: 'payments', label: 'Payments', description: 'Read payment records and their provider status.',
    table: 'payments', idKey: 'id', select: 'id,subscription_id,user_id,gateway_name,amount,currency_code,status,paid_at,failure_code,created_at',
    columns: [{ key: 'gateway_name', label: 'Gateway' }, { key: 'amount', label: 'Amount' }, { key: 'currency_code', label: 'Currency' }, { key: 'status', label: 'Status' }, { key: 'created_at', label: 'Created' }],
    fields: [], create: false, remove: false, search: 'gateway_name',
  },
  {
    key: 'audit_logs', label: 'Audit logs', description: 'Review recorded platform actions.',
    table: 'audit_logs', idKey: 'id', select: 'id,actor_user_id,action,entity_type,entity_id,details,ip_address,user_agent,created_at',
    columns: [{ key: 'action', label: 'Action' }, { key: 'entity_type', label: 'Record type' }, { key: 'entity_id', label: 'Record ID' }, { key: 'created_at', label: 'Time' }],
    fields: [], create: false, remove: false, search: 'action',
  },
]

export function getResource(key: string) {
  return resources.find((resource) => resource.key === key)
}

export const navigationGroups = [
  { label: 'Workspace', items: ['overview'] },
  { label: 'People & requests', items: ['members', 'clients', 'membership_applications', 'memberships', 'client_service_requests', 'partnership_enquiries'] },
  { label: 'Community', items: ['work_opportunities', 'applications', 'program_enrollments', 'reviews', 'recognition_nominations'] },
  { label: 'Platform', items: ['events', 'event_media', 'programs', 'articles', 'professional_categories', 'professional_roles', 'skills', 'professional_tools', 'taxonomy_aliases', 'professional_role_categories', 'skill_categories', 'professional_tool_categories', 'taxonomy_suggestions', 'admin_taxonomy_usage', 'recognition_awards', 'media_assets'] },
  { label: 'Business', items: ['subscription_plans', 'subscriptions', 'payments', 'audit_logs'] },
] as const
