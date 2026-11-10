'use client'

import Link from 'next/link'
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from 'react'
import { ArrowRight, Bell, BriefcaseBusiness, Building2, CalendarDays, Check, CircleUserRound, FileText, LogOut, Plus, Search, ShieldCheck, Trash2, UserRound, Users, X } from 'lucide-react'
import { signOut } from '@/app/auth/sign-out'
import { createClient } from '@/lib/supabase/client'
import type { AccountType } from '@/lib/supabase/shared'

type Row = Record<string, unknown>
type Section = 'overview' | 'profile' | 'opportunities' | 'applications' | 'discovery' | 'saved' | 'search-history' | 'events' | 'requests' | 'enquiries' | 'membership' | 'notifications' | 'subscription'
type Props = { role: AccountType; email: string; name?: string | null }
type OpportunitySearchFilters = { query: string; location: string; category: string; skill: string; role: string; tool: string; arrangement: string; minimumExperience: string; maximumBudget: string }

const memberNav: { key: Section; label: string; icon: typeof UserRound }[] = [
  { key: 'overview', label: 'Overview', icon: CircleUserRound },
  { key: 'profile', label: 'My profile & portfolio', icon: UserRound },
  { key: 'opportunities', label: 'Work opportunities', icon: BriefcaseBusiness },
  { key: 'applications', label: 'My applications', icon: FileText },
  { key: 'membership', label: 'Membership applications', icon: FileText },
  { key: 'enquiries', label: 'Client enquiries', icon: FileText },
  { key: 'events', label: 'Programs & events', icon: CalendarDays },
  { key: 'notifications', label: 'Notifications', icon: Bell },
  { key: 'subscription', label: 'Trial & subscription', icon: ShieldCheck },
]
const clientNav: { key: Section; label: string; icon: typeof UserRound }[] = [
  { key: 'overview', label: 'Overview', icon: CircleUserRound },
  { key: 'profile', label: 'Company profile', icon: Building2 },
  { key: 'discovery', label: 'Discover professionals', icon: Search },
  { key: 'saved', label: 'Saved professionals', icon: Users },
  { key: 'search-history', label: 'Recent searches', icon: Search },
  { key: 'opportunities', label: 'My opportunities', icon: BriefcaseBusiness },
  { key: 'applications', label: 'Applications received', icon: FileText },
  { key: 'requests', label: 'CCB service requests', icon: FileText },
  { key: 'events', label: 'Programs & events', icon: CalendarDays },
  { key: 'notifications', label: 'Notifications', icon: Bell },
  { key: 'subscription', label: 'Trial & subscription', icon: ShieldCheck },
]

const blankMember = { display_name: '', headline: '', bio: '', location: '', country_code: '', years_experience: '', availability: 'available', professional_interests: '', contact_preference: 'platform', portfolio_website: '', is_public: false, insights_sharing_enabled: false, profile_media_id: '' }
const blankClient = { display_name: '', company_name: '', organization_type: '', industry: '', description: '', website_url: '', location: '', country_code: '', business_email: '', business_phone: '', logo_media_id: '' }
const blankOpportunitySearch: OpportunitySearchFilters = { query: '', location: '', category: '', skill: '', role: '', tool: '', arrangement: '', minimumExperience: '', maximumBudget: '' }
const val = (row: Row | null | undefined, key: string) => row?.[key] == null ? '' : String(row[key])
const errText = (error: unknown) => error instanceof Error ? error.message : 'Something went wrong. Please try again.'
const asRows = (value: unknown): Row[] => Array.isArray(value) ? value as Row[] : []

export default function Workspace({ role, email, name }: Props) {
  const isMember = role === 'member'
  const nav = isMember ? memberNav : clientNav
  const firstName = name?.trim().split(/\s+/)[0] || email.split('@')[0] || 'there'
  const [section, setSection] = useState<Section>('overview')
  const [userId, setUserId] = useState('')
  const [rows, setRows] = useState<Row[]>([])
  const [overviewStats, setOverviewStats] = useState({ activityCount: 0, upcomingEvents: 0, unreadNotifications: 0, profileCompletion: 0, trialStatus: 'No trial record' })
  const [profile, setProfile] = useState<Row>(isMember ? blankMember : blankClient)
  const [categories, setCategories] = useState<Row[]>([])
  const [skills, setSkills] = useState<Row[]>([])
  const [professionalRoles, setProfessionalRoles] = useState<Row[]>([])
  const [professionalTools, setProfessionalTools] = useState<Row[]>([])
  const [selectedCategories, setSelectedCategories] = useState<string[]>([])
  const [selectedSkills, setSelectedSkills] = useState<string[]>([])
  const [selectedRoles, setSelectedRoles] = useState<string[]>([])
  const [selectedTools, setSelectedTools] = useState<string[]>([])
  const [roleFilter, setRoleFilter] = useState('')
  const [toolFilter, setToolFilter] = useState('')
  const [portfolio, setPortfolio] = useState<Row[]>([])
  const [socials, setSocials] = useState<Row[]>([])
  const [savedIds, setSavedIds] = useState<string[]>([])
  const [query, setQuery] = useState('')
  const [searchLocation, setSearchLocation] = useState('')
  const [minimumExperience, setMinimumExperience] = useState('')
  const [maximumExperience, setMaximumExperience] = useState('')
  const [minimumExpectedRate, setMinimumExpectedRate] = useState('')
  const [maximumExpectedRate, setMaximumExpectedRate] = useState('')
  const [minimumRating, setMinimumRating] = useState('')
  const [availabilityFilter, setAvailabilityFilter] = useState('')
  const [discoveryPage, setDiscoveryPage] = useState(0)
  const [discoveryTotal, setDiscoveryTotal] = useState(0)
  const [opportunityPage, setOpportunityPage] = useState(0)
  const [opportunityTotal, setOpportunityTotal] = useState(0)
  const [opportunitySearch, setOpportunitySearch] = useState<OpportunitySearchFilters>(blankOpportunitySearch)
  const [opportunityFormKey, setOpportunityFormKey] = useState(0)
  const [loading, setLoading] = useState(true)
  const [loadedSection, setLoadedSection] = useState<Section | null>(null)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const loadSequence = useRef(0)
  const initialSectionResolved = useRef(false)

  const activeNav = nav.find((item) => item.key === section)
  const supabase = useMemo(() => createClient(), [])

  const load = useCallback(async (requestedPage?: number, memberFilters: OpportunitySearchFilters = opportunitySearch) => {
    const requestId = ++loadSequence.current
    const requestSection = section
    setLoading(true)
    setError('')
    try {
      const { data: authData, error: authError } = await supabase.auth.getUser()
      if (authError || !authData.user) throw authError ?? new Error('Your session has expired. Sign in again.')
      const currentId = authData.user.id
      setUserId(currentId)

      if (section === 'overview') {
        const table = isMember ? 'applications' : 'work_opportunities'
        const filter = isMember ? 'member_id' : 'client_id'
        const [{ data, count, error: listError }, { count: upcomingEvents, error: eventsError }, { count: unreadNotifications, error: notificationsError }, { data: profileData, error: profileError }, { data: subscriptions, error: subscriptionsError }] = await Promise.all([
          supabase.from(table).select('*', { count: 'exact' }).eq(filter, currentId).order(isMember ? 'submitted_at' : 'created_at', { ascending: false }).limit(5),
          supabase.from('events').select('id', { count: 'exact', head: true }).eq('status', 'published').gte('starts_at', new Date().toISOString()),
          supabase.from('notifications').select('id', { count: 'exact', head: true }).eq('user_id', currentId).is('read_at', null),
          supabase.from(isMember ? 'member_profiles' : 'client_profiles').select('*').eq('user_id', currentId).maybeSingle(),
          supabase.from('subscriptions').select('status,trial_ends_at,current_period_ends_at').eq('user_id', currentId).order('created_at', { ascending: false }).limit(1),
        ])
        if (listError) throw listError
        if (eventsError) throw eventsError
        if (notificationsError) throw notificationsError
        if (profileError) throw profileError
        if (subscriptionsError) throw subscriptionsError
        setRows((data ?? []) as Row[])
        const fields = isMember
          ? ['headline', 'bio', 'location', 'profile_media_id', 'portfolio_website']
          : ['company_name', 'organization_type', 'industry', 'description', 'website_url', 'location', 'logo_media_id']
        const completion = fields.filter((key) => Boolean(profileData?.[key])).length
        const currentSubscription = subscriptions?.[0]
        setOverviewStats({
          activityCount: count ?? 0,
          upcomingEvents: upcomingEvents ?? 0,
          unreadNotifications: unreadNotifications ?? 0,
          profileCompletion: Math.round(completion / fields.length * 100),
          trialStatus: currentSubscription?.status === 'trial' && currentSubscription.trial_ends_at ? `Trial ends ${new Date(currentSubscription.trial_ends_at).toLocaleDateString()}` : currentSubscription?.status ?? 'No trial record',
        })
      } else if (section === 'profile') {
        const table = isMember ? 'member_profiles' : 'client_profiles'
        const { data, error: profileError } = await supabase.from(table).select('*').eq('user_id', currentId).maybeSingle()
        if (profileError) throw profileError
        const { data: identity, error: identityError } = await supabase.from('user_profiles').select('display_name').eq('id', currentId).maybeSingle()
        if (identityError) throw identityError
        setProfile({ ...(isMember ? blankMember : blankClient), display_name: identity?.display_name ?? name ?? '', ...(data ?? {}) } as Row)
        if (isMember) {
          const [categoryList, skillList, roleList, toolList, memberCats, memberSkills, memberRoleRows, memberToolRows, portfolioList, socialList] = await Promise.all([
            supabase.from('professional_categories').select('id,name').eq('is_active', true).order('sort_order').limit(300),
            supabase.from('skills').select('id,name').eq('is_active', true).order('name').limit(500),
            supabase.from('professional_roles').select('id,name').eq('is_active', true).order('name').limit(500),
            supabase.from('professional_tools').select('id,name').eq('is_active', true).order('name').limit(500),
            supabase.from('member_categories').select('category_id').eq('member_id', currentId),
            supabase.from('member_skills').select('skill_id').eq('member_id', currentId),
            supabase.from('member_roles').select('role_id').eq('member_id', currentId),
            supabase.from('member_tools').select('tool_id').eq('member_id', currentId),
            supabase.from('portfolio_items').select('*,portfolio_item_media(media_asset_id,media_assets(id,original_filename,mime_type,file_size_bytes))').eq('member_id', currentId).order('sort_order').limit(100),
            supabase.from('social_accounts').select('id,provider,profile_url,sharing_enabled,authorization_status').eq('member_id', currentId).order('created_at'),
          ])
          for (const result of [categoryList, skillList, roleList, toolList, memberCats, memberSkills, memberRoleRows, memberToolRows, portfolioList, socialList]) if (result.error) throw result.error
          setCategories((categoryList.data ?? []) as Row[])
          setSkills((skillList.data ?? []) as Row[])
          setProfessionalRoles((roleList.data ?? []) as Row[])
          setProfessionalTools((toolList.data ?? []) as Row[])
          setSelectedCategories((memberCats.data ?? []).map((r) => String(r.category_id)))
          setSelectedSkills((memberSkills.data ?? []).map((r) => String(r.skill_id)))
          setSelectedRoles((memberRoleRows.data ?? []).map((r) => String(r.role_id)))
          setSelectedTools((memberToolRows.data ?? []).map((r) => String(r.tool_id)))
          setPortfolio((portfolioList.data ?? []) as Row[])
          setSocials((socialList.data ?? []) as Row[])
        }
      } else if (section === 'opportunities') {
        const [categoryResult, skillResult, roleResult, toolResult] = await Promise.all([
          supabase.from('professional_categories').select('id,name').eq('is_active', true).order('sort_order').limit(300),
          supabase.from('skills').select('id,name').eq('is_active', true).order('name').limit(500),
          supabase.from('professional_roles').select('id,name').eq('is_active', true).order('name').limit(500),
          supabase.from('professional_tools').select('id,name').eq('is_active', true).order('name').limit(500),
        ])
        if (categoryResult.error) throw categoryResult.error
        if (skillResult.error) throw skillResult.error
        if (roleResult.error) throw roleResult.error
        if (toolResult.error) throw toolResult.error
        setCategories((categoryResult.data ?? []) as Row[])
        setSkills((skillResult.data ?? []) as Row[])
        setProfessionalRoles((roleResult.data ?? []) as Row[])
        setProfessionalTools((toolResult.data ?? []) as Row[])
        let data: Row[] | null = null
        let listError: { message: string } | null = null
        if (isMember) {
          const { data: ranked, error: rankError } = await supabase.rpc('get_personalized_opportunities', {
            p_page: requestedPage ?? opportunityPage,
            p_page_size: 20,
            p_query: memberFilters.query.trim(),
            p_location: memberFilters.location.trim(),
            p_category_id: memberFilters.category || null,
            p_skill_id: memberFilters.skill || null,
            p_role_id: memberFilters.role || null,
            p_tool_id: memberFilters.tool || null,
            p_work_arrangement: memberFilters.arrangement || null,
            p_min_experience: memberFilters.minimumExperience === '' ? null : Number(memberFilters.minimumExperience),
            p_max_budget: memberFilters.maximumBudget === '' ? null : Number(memberFilters.maximumBudget),
          })
          if (rankError) throw rankError
          const rankedRows = (ranked ?? []) as Row[]
          setOpportunityTotal(Number(rankedRows[0]?.total_count ?? 0))
          if (rankedRows.length) {
            const { data: opportunities, error } = await supabase.from('work_opportunities').select('id,client_id,title,description,budget_min,budget_max,currency_code,budget_type,budget_negotiable,payment_terms,work_type,location,work_arrangement,deadline,application_deadline,experience_min_years,experience_max_years,status,created_at,opportunity_categories(category_id,professional_categories(name)),opportunity_skills(skill_id,is_mandatory,skills(name,taxonomy_aliases(alias))),opportunity_roles(role_id,professional_roles(name,taxonomy_aliases(alias))),opportunity_tools(tool_id,professional_tools(name,taxonomy_aliases(alias)))').in('id', rankedRows.map((r) => String(r.opportunity_id)))
            data = (opportunities ?? []).sort((a, b) => rankedRows.findIndex((r) => r.opportunity_id === a.id) - rankedRows.findIndex((r) => r.opportunity_id === b.id)) as Row[]
            listError = error
          } else data = []
        } else {
          const result = await supabase.from('work_opportunities').select('*').eq('client_id', currentId).order('created_at', { ascending: false }).limit(100)
          data = (result.data ?? []) as Row[]
          listError = result.error
        }
        if (listError) throw listError
        setRows(data ?? [])
      } else if (section === 'applications') {
        const { data, error: listError } = isMember
          ? await supabase.from('applications').select('id,opportunity_id,cover_message,status,client_message,submitted_at,status_updated_at,application_status_history(id,from_status,to_status,changed_at),work_opportunities(title,status,client_id)').eq('member_id', currentId).order('submitted_at', { ascending: false }).limit(100)
          : await supabase.from('applications').select('id,opportunity_id,member_id,cover_message,status,client_message,submitted_at,status_updated_at,application_status_history(id,from_status,to_status,changed_at),work_opportunities!inner(title,client_id,status),member_profiles(headline,location,user_profiles(display_name))').eq('work_opportunities.client_id', currentId).order('submitted_at', { ascending: false }).limit(100)
        if (listError) throw listError
        setRows((data ?? []) as Row[])
      } else if (section === 'discovery') {
        const [categoryResult, skillResult, roleResult, toolResult] = await Promise.all([
          supabase.from('professional_categories').select('id,name').eq('is_active', true).order('sort_order').limit(300),
          supabase.from('skills').select('id,name').eq('is_active', true).order('name').limit(500),
          supabase.from('professional_roles').select('id,name').eq('is_active', true).order('name').limit(500),
          supabase.from('professional_tools').select('id,name').eq('is_active', true).order('name').limit(500),
        ])
        if (categoryResult.error) throw categoryResult.error
        if (skillResult.error) throw skillResult.error
        if (roleResult.error) throw roleResult.error
        if (toolResult.error) throw toolResult.error
        setCategories((categoryResult.data ?? []) as Row[])
        setSkills((skillResult.data ?? []) as Row[])
        setProfessionalRoles((roleResult.data ?? []) as Row[])
        setProfessionalTools((toolResult.data ?? []) as Row[])
        const categoryRelation = selectedCategories.length ? 'member_categories!inner(category_id,professional_categories(name))' : 'member_categories(category_id,professional_categories(name))'
        const skillRelation = selectedSkills.length ? 'member_skills!inner(skill_id,skills(name))' : 'member_skills(skill_id,skills(name))'
        const pageIndex = requestedPage ?? discoveryPage
        const roleRelation = roleFilter ? 'member_roles!inner(role_id,professional_roles(name))' : 'member_roles(role_id,professional_roles(name))'
        const toolRelation = toolFilter ? 'member_tools!inner(tool_id,professional_tools(name))' : 'member_tools(tool_id,professional_tools(name))'
        let taxonomyMatches: Row[] | null = null
        if (query.trim() || minimumRating) {
          const { data: matches, error: taxonomySearchError } = await supabase.rpc('search_member_profiles', { p_query: query.trim().slice(0, 160), p_minimum_rating: minimumRating ? Number(minimumRating) : null, p_minimum_reviews: null })
          if (taxonomySearchError) throw taxonomySearchError
          taxonomyMatches = (matches ?? []) as Row[]
        }
        let request = supabase.from('member_profiles').select(`user_id,headline,bio,location,country_code,years_experience,availability,expected_rate_min,expected_rate_max,expected_rate_period,rate_negotiable,profile_media_id,user_profiles(display_name,avatar_url),${categoryRelation},${skillRelation},${roleRelation},${toolRelation},portfolio_items(id,title,description,project_url,visibility,portfolio_item_media(media_asset_id,media_assets(id,original_filename,mime_type,file_size_bytes)))`, { count: 'exact' }).eq('is_public', true).order('updated_at', { ascending: false }).order('user_id', { ascending: true }).range(pageIndex * 20, pageIndex * 20 + 19)
        if (taxonomyMatches) request = taxonomyMatches.length ? request.in('user_id', taxonomyMatches.map((match) => String(match.member_id))) : request.eq('user_id', '00000000-0000-0000-0000-000000000000')
        if (searchLocation.trim()) request = request.ilike('location', `%${searchLocation.trim().replace(/[%,()]/g, '')}%`)
        if (selectedCategories.length) request = request.eq('member_categories.category_id', selectedCategories[0])
        if (selectedSkills.length) request = request.eq('member_skills.skill_id', selectedSkills[0])
        if (roleFilter) request = request.eq('member_roles.role_id', roleFilter)
        if (toolFilter) request = request.eq('member_tools.tool_id', toolFilter)
        if (minimumExperience !== '') request = request.gte('years_experience', Number(minimumExperience))
        if (maximumExperience !== '') request = request.lte('years_experience', Number(maximumExperience))
        if (minimumExpectedRate !== '') request = request.or(`expected_rate_max.is.null,expected_rate_max.gte.${Number(minimumExpectedRate)}`)
        if (maximumExpectedRate !== '') request = request.or(`expected_rate_min.is.null,expected_rate_min.lte.${Number(maximumExpectedRate)}`)
        if (availabilityFilter) request = request.eq('availability', availabilityFilter)
        const [{ data, count, error: searchError }, { data: saved, error: savedError }] = await Promise.all([
          request,
          supabase.from('saved_members').select('member_id').eq('client_id', currentId),
        ])
        if (searchError) throw searchError
        if (savedError) throw savedError
        const ratingByMember = new Map((taxonomyMatches ?? []).map((match) => [String(match.member_id), match]))
        setRows(((data ?? []) as Row[]).map((member) => ({ ...member, average_rating: ratingByMember.get(String(member.user_id))?.average_rating ?? null, review_count: ratingByMember.get(String(member.user_id))?.review_count ?? 0 })))
        setDiscoveryTotal(count ?? 0)
        setSavedIds((saved ?? []).map((r) => String(r.member_id)))
        if (pageIndex === 0) await supabase.from('client_search_history').insert({ client_id: currentId, search_filters: { query: query.trim(), location: searchLocation.trim(), category_id: selectedCategories[0] ?? null, skill_id: selectedSkills[0] ?? null, role_id: roleFilter || null, tool_id: toolFilter || null, minimum_experience: minimumExperience || null, maximum_experience: maximumExperience || null, minimum_expected_rate: minimumExpectedRate || null, maximum_expected_rate: maximumExpectedRate || null, minimum_rating: minimumRating || null, availability: availabilityFilter || null } })
      } else if (section === 'saved') {
        const { data, error: listError } = await supabase.from('saved_members').select('member_id,created_at,member_profiles(user_id,headline,bio,location,years_experience,availability,expected_rate_min,expected_rate_max,expected_rate_period,rate_negotiable,profile_media_id,user_profiles(display_name,avatar_url),member_categories(category_id,professional_categories(name)),member_skills(skill_id,skills(name)),member_roles(role_id,professional_roles(name)),member_tools(tool_id,professional_tools(name)),portfolio_items(id,title,description,project_url,visibility,portfolio_item_media(media_asset_id,media_assets(id,original_filename,mime_type,file_size_bytes))))').eq('client_id', currentId).order('created_at', { ascending: false }).limit(100)
        if (listError) throw listError
        setRows((data ?? []) as Row[])
      } else if (section === 'events') {
        const [{ data: publicEvents, error: eventError }, { data: publicPrograms, error: programError }, { data: enrollments, error: enrollmentError }] = await Promise.all([
          supabase.from('events').select('id,title,slug,summary,description,starts_at,ends_at,timezone,venue_name,venue_address,is_online,registration_closes_at,featured_media_id,event_category,event_visibility,external_rsvp_url,rsvp_closed,status').eq('status', 'published').eq('event_visibility', 'public').order('starts_at', { ascending: true }).limit(50),
          supabase.from('programs').select('id,title,slug,summary,description,starts_on,ends_on,featured_media_id').eq('status', 'published').order('starts_on', { ascending: false }).limit(50),
          supabase.from('program_enrollments').select('id,program_id,status,enrolled_at').eq('user_id', currentId).order('enrolled_at', { ascending: false }).limit(100),
        ])
        if (eventError) throw eventError
        if (programError) throw programError
        if (enrollmentError) throw enrollmentError
        setRows([...(publicEvents ?? []) as Row[], { _programs: publicPrograms ?? [], _enrollments: enrollments ?? [] }])
      } else if (section === 'requests') {
        const { data, error: listError } = await supabase.from('client_service_requests').select('id,request_type,subject,description,status,submitted_at,updated_at').eq('client_id', currentId).order('submitted_at', { ascending: false }).limit(100)
        if (listError) throw listError
        setRows((data ?? []) as Row[])
      } else if (section === 'enquiries') {
        const { data, error: listError } = await supabase.from('member_enquiries').select('id,client_id,subject,message,status,created_at').eq('member_id', currentId).order('created_at', { ascending: false }).limit(100)
        if (listError) throw listError
        setRows((data ?? []) as Row[])
      } else if (section === 'membership') {
        const { data, error: listError } = await supabase.from('membership_applications').select('id,requested_category,message,status,submitted_at,updated_at').eq('user_id', currentId).order('submitted_at', { ascending: false }).limit(100)
        if (listError) throw listError
        setRows((data ?? []) as Row[])
      } else if (section === 'search-history') {
        const { data, error: listError } = await supabase.from('client_search_history').select('id,search_filters,searched_at').eq('client_id', currentId).order('searched_at', { ascending: false }).limit(100)
        if (listError) throw listError
        setRows((data ?? []) as Row[])
      } else if (section === 'notifications') {
        const { data, error: listError } = await supabase.from('notifications').select('id,notification_type,title,message,target_url,read_at,created_at').eq('user_id', currentId).order('created_at', { ascending: false }).limit(100)
        if (listError) throw listError
        setRows((data ?? []) as Row[])
      } else if (section === 'subscription') {
        const { data, error: listError } = await supabase.from('subscriptions').select('id,status,trial_starts_at,trial_ends_at,starts_at,current_period_ends_at,renews_at,cancelled_at,subscription_plans(name,description,billing_period,price_amount,currency_code),subscription_entitlements(feature_key,enabled)').eq('user_id', currentId).order('created_at', { ascending: false }).limit(10)
        if (listError) throw listError
        setRows((data ?? []) as Row[])
      }
    } catch (caught) {
      setError(`${errText(caught)} If this is a new Supabase setup, run the project migrations first.`)
    } finally {
      if (loadSequence.current === requestId) {
        setLoadedSection(requestSection)
        setLoading(false)
      }
    }
  }, [availabilityFilter, discoveryPage, isMember, maximumExpectedRate, maximumExperience, minimumExpectedRate, minimumExperience, minimumRating, name, opportunityPage, opportunitySearch, query, roleFilter, section, searchLocation, selectedCategories, selectedSkills, supabase, toolFilter])

  const loadRef = useRef(load)
  loadRef.current = load

  useEffect(() => {
    if (!initialSectionResolved.current) {
      initialSectionResolved.current = true
      const requestedSection = new URLSearchParams(window.location.search).get('section')
      if (requestedSection && nav.some((item) => item.key === requestedSection) && requestedSection !== section) {
        setSection(requestedSection as Section)
        return
      }
    }
    void loadRef.current()
  }, [section])

  function searchMemberOpportunities(filters: OpportunitySearchFilters) {
    setOpportunitySearch(filters)
    setOpportunityPage(0)
    void load(0, filters)
  }

  function updateProfile(key: string, value: unknown) {
    setProfile((current) => ({ ...current, [key]: value }))
  }

  async function saveProfile(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setSaving(true); setError(''); setNotice('')
    try {
      if (!userId) throw new Error('Sign in again to save your profile.')
      const displayName = String(profile.display_name ?? '').trim()
      if (displayName.length < 2) throw new Error('Enter your full name.')
      const { error: nameError } = await supabase.from('user_profiles').update({ display_name: displayName }).eq('id', userId)
      if (nameError) throw nameError
      if (isMember) {
    const interests = String(profile.professional_interests ?? '').split(',').map((item) => item.trim()).filter(Boolean).slice(0, 50)
        const values = { ...profile, user_id: userId, years_experience: profile.years_experience === '' ? null : Number(profile.years_experience), expected_rate_min: val(profile, 'expected_rate_min') === '' ? null : Number(profile.expected_rate_min), expected_rate_max: val(profile, 'expected_rate_max') === '' ? null : Number(profile.expected_rate_max), professional_interests: interests, profile_media_id: profile.profile_media_id || null }
        delete (values as Row).display_name
        delete (values as Row).created_at; delete (values as Row).updated_at; delete (values as Row).verified_at
        const { error: saveError } = await supabase.from('member_profiles').upsert(values, { onConflict: 'user_id' })
        if (saveError) throw saveError
        const { error: categoryDeleteError } = await supabase.from('member_categories').delete().eq('member_id', userId)
        if (categoryDeleteError) throw categoryDeleteError
        if (selectedCategories.length) {
          const categoryRows = selectedCategories.map((category_id, index) => ({ member_id: userId, category_id, is_primary: index === 0 }))
          const { error: categoryError } = await supabase.from('member_categories').insert(categoryRows)
          if (categoryError) throw categoryError
        }
        const { error: skillDeleteError } = await supabase.from('member_skills').delete().eq('member_id', userId)
        if (skillDeleteError) throw skillDeleteError
        if (selectedSkills.length) {
          const skillRows = selectedSkills.map((skill_id) => ({ member_id: userId, skill_id, proficiency: 'intermediate' }))
          const { error: skillError } = await supabase.from('member_skills').insert(skillRows)
          if (skillError) throw skillError
        }
        for (const [table, key, ids] of [['member_roles', 'role_id', selectedRoles], ['member_tools', 'tool_id', selectedTools]] as const) {
          const { error: clearError } = await supabase.from(table).delete().eq('member_id', userId)
          if (clearError) throw clearError
          if (ids.length) {
            const { error: insertError } = await supabase.from(table).insert(ids.map((id) => ({ member_id: userId, [key]: id })))
            if (insertError) throw insertError
          }
        }
        const { error: preferenceDeleteError } = await supabase.from('member_work_preferences').delete().eq('member_id', userId)
        if (preferenceDeleteError) throw preferenceDeleteError
        const arrangements = Array.isArray(profile.work_preferences) ? profile.work_preferences as string[] : []
        if (arrangements.length) {
          const { error: preferenceError } = await supabase.from('member_work_preferences').insert(arrangements.map((work_arrangement) => ({ member_id: userId, work_arrangement })))
          if (preferenceError) throw preferenceError
        }
      } else {
        if (!String(profile.company_name ?? '').trim()) throw new Error('Enter your organisation name.')
        const values = { ...profile, user_id: userId, logo_media_id: profile.logo_media_id || null }
        delete (values as Row).display_name
        delete (values as Row).created_at; delete (values as Row).updated_at; delete (values as Row).verified_at; delete (values as Row).verification_status
        const { error: saveError } = await supabase.from('client_profiles').upsert(values, { onConflict: 'user_id' })
        if (saveError) throw saveError
      }
      setNotice('Your profile has been saved.')
      await load()
    } catch (caught) { setError(errText(caught)) } finally { setSaving(false) }
  }

  async function uploadPrivateMedia(file: File, purpose: 'profile' | 'portfolio') {
    const response = await fetch('/api/media', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ filename: file.name, mimeType: file.type, size: file.size, purpose }) })
    const signed = await response.json()
    if (!response.ok) throw new Error(signed.error ?? 'Could not start the private upload.')
    const upload = await fetch(signed.uploadUrl, { method: 'PUT', headers: { 'content-type': file.type }, body: file })
    if (!upload.ok) throw new Error('Cloudflare rejected the upload. Check the private R2 bucket CORS settings.')
    const complete = await fetch('/api/media', { method: 'PUT', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ objectKey: signed.objectKey, filename: file.name, mimeType: file.type, size: file.size, purpose, altText: purpose === 'portfolio' ? file.name : isMember ? 'Member profile photo' : 'Client company logo' }) })
    const result = await complete.json()
    if (!complete.ok) throw new Error(result.error ?? 'Could not save the private file record.')
    return result.media as Row
  }

  async function uploadProfileImage(file?: File) {
    if (!file) return
    setSaving(true); setError(''); setNotice('')
    try {
      if (!userId) throw new Error('Your profile is still loading. Please try again in a moment.')
      const media = await uploadPrivateMedia(file, 'profile')
      const column = isMember ? 'profile_media_id' : 'logo_media_id'
      const table = isMember ? 'member_profiles' : 'client_profiles'
      const { error: attachError } = await supabase.from(table).upsert({ user_id: userId, [column]: media.id }, { onConflict: 'user_id' })
      if (attachError) throw attachError
      updateProfile(column, media.id)
      setNotice(`${isMember ? 'Profile photo' : 'Company logo'} uploaded and attached.`)
    } catch (caught) { setError(errText(caught)) } finally { setSaving(false) }
  }

  async function addPortfolio(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setError(''); setNotice('')
    const formElement = event.currentTarget
    const form = new FormData(formElement)
    const values = { member_id: userId, title: String(form.get('title') ?? '').trim(), description: String(form.get('description') ?? '').trim() || null, project_url: String(form.get('project_url') ?? '').trim() || null, visibility: String(form.get('visibility') ?? 'public'), sort_order: portfolio.length }
    setSaving(true)
    try {
      const { data: item, error: insertError } = await supabase.from('portfolio_items').insert(values).select('id').single()
      if (insertError || !item) throw insertError ?? new Error('Could not create the portfolio item.')
      const files = form.getAll('portfolio_files').filter((file): file is File => file instanceof File && file.size > 0)
      if (files.length > 5) throw new Error('Attach up to five portfolio files at a time.')
      const mediaRows = await Promise.all(files.map((file) => uploadPrivateMedia(file, 'portfolio')))
      if (mediaRows.length) {
        const { error: attachError } = await supabase.from('portfolio_item_media').insert(mediaRows.map((media) => ({ portfolio_item_id: item.id, media_asset_id: media.id })))
        if (attachError) throw attachError
      }
      formElement.reset(); setNotice('Portfolio item saved with private media.'); await load()
    } catch (caught) { setError(errText(caught)) } finally { setSaving(false) }
  }

  async function removePortfolio(id: string) {
    const { error: deleteError } = await supabase.from('portfolio_items').delete().eq('id', id).eq('member_id', userId)
    if (deleteError) setError(errText(deleteError)); else await load()
  }

  async function addSocialAccount(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); const formElement = event.currentTarget; const form = new FormData(formElement)
    const { error: insertError } = await supabase.from('social_accounts').insert({ member_id: userId, provider: String(form.get('provider')), profile_url: String(form.get('profile_url')).trim(), sharing_enabled: Boolean(form.get('sharing_enabled')) })
    if (insertError) setError(errText(insertError)); else { formElement.reset(); setNotice('Social profile link saved. Insights stay disconnected until an approved Meta connection is configured.'); await load() }
  }

  async function suggestTaxonomy(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const formElement = event.currentTarget
    const form = new FormData(formElement)
    const { error: suggestionError } = await supabase.from('taxonomy_suggestions').insert({ submitted_by: userId, suggestion_type: String(form.get('suggestion_type')), name: String(form.get('name') ?? '').trim(), description: String(form.get('description') ?? '').trim() || null })
    if (suggestionError) setError(errText(suggestionError))
    else { formElement.reset(); setNotice('Suggestion sent to CCB Admin for review.') }
  }

  async function createOpportunity(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); const form = new FormData(event.currentTarget)
    setSaving(true); setError(''); setNotice('')
    const num = (key: string) => String(form.get(key) ?? '') === '' ? null : Number(form.get(key))
    const date = (key: string) => String(form.get(key) ?? '') || null
    const formElement = event.currentTarget
    const localDeadline = String(form.get('application_deadline') ?? '')
    const values = { client_id: userId, title: String(form.get('title') ?? '').trim(), description: String(form.get('description') ?? '').trim(), budget_min: num('budget_min'), budget_max: num('budget_max'), currency_code: 'INR', professionals_required: num('professionals_required'), experience_min_years: num('experience_min_years'), location: String(form.get('location') ?? '').trim() || null, work_arrangement: String(form.get('work_arrangement') ?? '') || null, start_date: date('start_date'), deadline: date('deadline'), application_deadline: localDeadline ? new Date(localDeadline).toISOString() : null, additional_requirements: String(form.get('additional_requirements') ?? '').trim() || null, budget_type: String(form.get('budget_type') ?? '') || null, budget_negotiable: form.get('budget_negotiable') === 'on', payment_terms: String(form.get('payment_terms') ?? '').trim() || null, work_type: String(form.get('work_type') ?? '') || null, experience_max_years: num('experience_max_years'), required_availability: String(form.get('required_availability') ?? '') || null, skills_match_mode: String(form.get('skills_match_mode') ?? 'any') }
    const { data: opportunity, error: insertError } = await supabase.from('work_opportunities').insert(values).select('id').single()
    if (insertError) setError(errText(insertError)); else {
      const categoryIds = form.getAll('category_ids').map(String)
      const skillIds = form.getAll('skill_ids').map(String)
      const roleIds = form.getAll('role_ids').map(String)
      const toolIds = form.getAll('tool_ids').map(String)
      if (categoryIds.length) {
        const { error: targetError } = await supabase.from('opportunity_categories').insert(categoryIds.map((category_id) => ({ opportunity_id: opportunity.id, category_id })))
        if (targetError) setError(`Draft saved, but its category filters could not be saved: ${errText(targetError)}`)
      }
      if (skillIds.length) {
        const mandatorySkills = new Set(form.getAll('mandatory_skill_ids').map(String))
        const { error: targetError } = await supabase.from('opportunity_skills').insert(skillIds.map((skill_id) => ({ opportunity_id: opportunity.id, skill_id, is_mandatory: mandatorySkills.has(skill_id) })))
        if (targetError) setError(`Draft saved, but its skill filters could not be saved: ${errText(targetError)}`)
      }
      if (roleIds.length) {
        const { error: targetError } = await supabase.from('opportunity_roles').insert(roleIds.map((role_id) => ({ opportunity_id: opportunity.id, role_id })))
        if (targetError) setError(`Draft saved, but its role filters could not be saved: ${errText(targetError)}`)
      }
      if (toolIds.length) {
        const { error: targetError } = await supabase.from('opportunity_tools').insert(toolIds.map((tool_id) => ({ opportunity_id: opportunity.id, tool_id })))
        if (targetError) setError(`Draft saved, but its tool filters could not be saved: ${errText(targetError)}`)
      }
      formElement.reset(); setOpportunityFormKey((key) => key + 1); setNotice('Draft saved. Publish it when the details are ready.'); await load()
    }
    setSaving(false)
  }

  async function updateOpportunity(id: string, event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    const numeric = (key: string) => String(form.get(key) ?? '') === '' ? null : Number(form.get(key))
    const { error: updateError } = await supabase.from('work_opportunities').update({
      title: String(form.get('title') ?? '').trim(),
      description: String(form.get('description') ?? '').trim(),
      location: String(form.get('location') ?? '').trim() || null,
      budget_min: numeric('budget_min'), budget_max: numeric('budget_max'),
      experience_min_years: numeric('experience_min_years'), experience_max_years: numeric('experience_max_years'),
      work_arrangement: String(form.get('work_arrangement') ?? '') || null,
      application_deadline: String(form.get('application_deadline') ?? '') ? new Date(String(form.get('application_deadline'))).toISOString() : null,
      deadline: String(form.get('deadline') ?? '') || null,
      budget_type: String(form.get('budget_type') ?? '') || null,
      budget_negotiable: form.get('budget_negotiable') === 'on',
      payment_terms: String(form.get('payment_terms') ?? '').trim() || null,
      work_type: String(form.get('work_type') ?? '') || null,
      required_availability: String(form.get('required_availability') ?? '') || null,
    }).eq('id', id).eq('client_id', userId)
    if (updateError) setError(errText(updateError))
    else { setNotice('Opportunity details updated.'); await load() }
  }

  async function setOpportunityStatus(id: string, status: string) {
    setError(''); setNotice('')
    const { error: updateError } = await supabase.rpc('set_opportunity_status', { p_opportunity_id: id, p_status: status })
    if (updateError) setError(errText(updateError)); else { setNotice(`Opportunity ${status.replaceAll('_', ' ')}.`); await load() }
  }

  async function applyToOpportunity(event: FormEvent<HTMLFormElement>, opportunityId: string) {
    event.preventDefault(); const form = new FormData(event.currentTarget)
    const { error: insertError } = await supabase.from('applications').insert({ opportunity_id: opportunityId, member_id: userId, cover_message: String(form.get('cover_message') ?? '').trim() || null })
    if (insertError) setError(errText(insertError)); else { setNotice('Your application was submitted. You can track its status here.'); await load() }
  }

  async function updateApplication(id: string, status: string, clientMessage: string) {
    const { error: updateError } = await supabase.rpc('set_application_status', { p_application_id: id, p_status: status, p_client_message: clientMessage || null })
    if (updateError) setError(errText(updateError)); else { setNotice('Application status updated.'); await load() }
  }

  async function withdrawApplication(id: string) {
    await updateApplication(id, 'withdrawn', '')
  }

  async function submitReview(event: FormEvent<HTMLFormElement>, opportunityId: string, reviewedUserId: string) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    const { error: reviewError } = await supabase.from('reviews').insert({ opportunity_id: opportunityId, reviewer_user_id: userId, reviewed_user_id: reviewedUserId, rating: Number(form.get('rating')), review_text: String(form.get('review_text') ?? '').trim() || null })
    if (reviewError) setError(reviewError.code === '23505' ? 'You already reviewed this engagement.' : errText(reviewError))
    else { setNotice('Review submitted for moderation.'); await load() }
  }

  async function toggleSaved(memberId: string) {
    setError('')
    if (savedIds.includes(memberId)) {
      const { error: deleteError } = await supabase.from('saved_members').delete().eq('client_id', userId).eq('member_id', memberId)
      if (deleteError) setError(errText(deleteError)); else setSavedIds((ids) => ids.filter((id) => id !== memberId))
    } else {
      const { error: insertError } = await supabase.from('saved_members').insert({ client_id: userId, member_id: memberId })
      if (insertError) setError(errText(insertError)); else setSavedIds((ids) => [...ids, memberId])
    }
  }

  async function createMemberEnquiry(event: FormEvent<HTMLFormElement>, memberId: string) {
    event.preventDefault(); const formElement = event.currentTarget; const form = new FormData(formElement)
    const { error: insertError } = await supabase.from('member_enquiries').insert({ client_id: userId, member_id: memberId, subject: String(form.get('subject') ?? '').trim(), message: String(form.get('message') ?? '').trim() })
    if (insertError) setError(errText(insertError)); else { formElement.reset(); setNotice('Your enquiry was sent to the Member.'); }
  }

  async function removeSaved(memberId: string) {
    const { error: deleteError } = await supabase.from('saved_members').delete().eq('client_id', userId).eq('member_id', memberId)
    if (deleteError) setError(errText(deleteError)); else await load()
  }

  async function enrollInProgram(programId: string) {
    const { error: enrollError } = await supabase.from('program_enrollments').insert({ program_id: programId, user_id: userId })
    if (enrollError) setError(errText(enrollError)); else { setNotice('Program enrollment submitted.'); await load() }
  }

  async function submitServiceRequest(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); const formElement = event.currentTarget; const form = new FormData(formElement)
    const { error: insertError } = await supabase.from('client_service_requests').insert({ client_id: userId, request_type: String(form.get('request_type')), subject: String(form.get('subject')).trim(), description: String(form.get('description')).trim() })
    if (insertError) setError(errText(insertError)); else { formElement.reset(); setNotice('Service request submitted to CCB.'); await load() }
  }

  async function markRead(id: string) {
    const { error: updateError } = await supabase.from('notifications').update({ read_at: new Date().toISOString() }).eq('id', id).eq('user_id', userId)
    if (updateError) setError(errText(updateError)); else setRows((items) => items.map((item) => item.id === id ? { ...item, read_at: new Date().toISOString() } : item))
  }

  const header = <div className="platform-heading"><div><span className="eyebrow">{isMember ? 'Member / Influencer' : 'Client / Business'}</span><h2>{activeNav?.label ?? 'Workspace'}</h2><p>{section === 'overview' ? `Welcome back, ${firstName}. Your workspace is connected to CCB India.` : sectionDescription(section, isMember)}</p></div>{section === 'overview' ? <span className="workspace-badge">{isMember ? 'Member workspace' : 'Client workspace'}</span> : null}</div>

  return (
    <main className="workspace-page platform-page">
      <header className="workspace-header"><Link className="auth-brand" href="/">CCB <span>INDIA</span></Link><div className="workspace-account"><div className="workspace-user"><span>{isMember ? 'Member / Influencer' : 'Client / Business'}</span><strong>{email}</strong></div><form action={signOut}><button className="workspace-signout" type="submit"><LogOut size={15}/> Sign out</button></form></div></header>
      <div className="platform-layout">
        <nav className="platform-nav" aria-label="Workspace sections">{nav.map(({ key, label, icon: Icon }) => <button key={key} className={section === key ? 'active' : ''} onClick={() => { setSection(key); setNotice(''); setError('') }}><Icon size={17}/><span>{label}</span></button>)}</nav>
        <div className="platform-main">{header}
          {error ? <div className="workspace-message is-error" role="alert">{error}</div> : null}
          {notice ? <div className="workspace-message is-success" role="status"><Check size={16}/>{notice}</div> : null}
          {loading && loadedSection !== section ? <div className="workspace-loading" role="status">Loading your workspace...</div> : <>
            {loading ? <p className="workspace-refreshing" role="status">Refreshing this section...</p> : null}
            {section === 'overview' && <Overview role={role} rows={rows} stats={overviewStats} onNavigate={setSection} />}
            {section === 'profile' && <ProfileForm isMember={isMember} profile={profile} updateProfile={updateProfile} saveProfile={saveProfile} saving={saving} categories={categories} skills={skills} roles={professionalRoles} tools={professionalTools} selectedCategories={selectedCategories} selectedSkills={selectedSkills} selectedRoles={selectedRoles} selectedTools={selectedTools} setSelectedCategories={setSelectedCategories} setSelectedSkills={setSelectedSkills} setSelectedRoles={setSelectedRoles} setSelectedTools={setSelectedTools} portfolio={portfolio} socials={socials} addPortfolio={addPortfolio} removePortfolio={removePortfolio} addSocialAccount={addSocialAccount} uploadProfileImage={uploadProfileImage} suggestTaxonomy={suggestTaxonomy} />}
            {section === 'opportunities' && (isMember ? <MemberOpportunities rows={rows} categories={categories} skills={skills} roles={professionalRoles} tools={professionalTools} apply={applyToOpportunity} page={opportunityPage} total={opportunityTotal} filters={opportunitySearch} setFilters={setOpportunitySearch} search={searchMemberOpportunities} setPage={(nextPage) => { setOpportunityPage(nextPage); void load(nextPage, opportunitySearch) }} /> : <ClientOpportunities key={opportunityFormKey} rows={rows} categories={categories} skills={skills} roles={professionalRoles} tools={professionalTools} create={createOpportunity} edit={updateOpportunity} setStatus={setOpportunityStatus} saving={saving} />)}
            {section === 'applications' && <Applications isMember={isMember} rows={rows} update={updateApplication} withdraw={withdrawApplication} review={submitReview} />}
            {section === 'discovery' && <Discovery rows={rows} query={query} setQuery={setQuery} location={searchLocation} setLocation={setSearchLocation} minimumExperience={minimumExperience} setMinimumExperience={setMinimumExperience} maximumExperience={maximumExperience} setMaximumExperience={setMaximumExperience} minimumRate={minimumExpectedRate} setMinimumRate={setMinimumExpectedRate} maximumRate={maximumExpectedRate} setMaximumRate={setMaximumExpectedRate} minimumRating={minimumRating} setMinimumRating={setMinimumRating} availability={availabilityFilter} setAvailability={setAvailabilityFilter} categories={categories} skills={skills} roles={professionalRoles} tools={professionalTools} category={selectedCategories[0] ?? ''} setCategory={(id) => setSelectedCategories(id ? [id] : [])} skill={selectedSkills[0] ?? ''} setSkill={(id) => setSelectedSkills(id ? [id] : [])} role={roleFilter} setRole={setRoleFilter} tool={toolFilter} setTool={setToolFilter} search={() => { setDiscoveryPage(0); void load(0) }} savedIds={savedIds} toggleSaved={toggleSaved} contact={createMemberEnquiry} page={discoveryPage} total={discoveryTotal} setPage={(nextPage) => { setDiscoveryPage(nextPage); void load(nextPage) }} />}
            {section === 'saved' && <SavedProfessionals rows={rows} remove={(id) => void removeSaved(id)} contact={createMemberEnquiry} />}
            {section === 'events' && <Events rows={rows} enroll={enrollInProgram} />}
            {section === 'requests' && <ServiceRequests rows={rows} submit={submitServiceRequest} />}
            {section === 'enquiries' && <MemberEnquiries rows={rows} />}
            {section === 'membership' && <MemberMembershipApplications rows={rows} />}
            {section === 'search-history' && <SearchHistory rows={rows} />}
            {section === 'notifications' && <Notifications rows={rows} markRead={markRead} />}
            {section === 'subscription' && <Subscriptions rows={rows} />}
          </>}
        </div>
      </div>
    </main>
  )
}

function sectionDescription(section: Section, isMember: boolean) {
  const descriptions: Record<Section, string> = {
    overview: '', profile: isMember ? 'Keep your professional profile, portfolio and social links up to date.' : 'Maintain the organisation details clients share with CCB.', opportunities: isMember ? 'Find published projects and apply from your Member account.' : 'Create drafts, publish opportunities and manage their lifecycle.', applications: isMember ? 'Track your applications and review status updates.' : 'Review applicants for opportunities published by your organisation.', discovery: 'Search public Member profiles and save professionals for later.', saved: 'Your saved professionals and portfolio links.', 'search-history': 'Review your recent Member discovery searches.', events: 'Browse published programs and events, register and view your ticket details.', requests: 'Submit and track requests for services from CCB.', enquiries: 'Review messages sent to you by eligible CCB Clients.', membership: 'Track your membership application submissions.', notifications: 'Updates about your applications and platform activity.', subscription: 'Review your trial, current subscription and available entitlements.',
  }
  return descriptions[section]
}

function Overview({ role, rows, stats, onNavigate }: { role: AccountType; rows: Row[]; stats: { activityCount: number; upcomingEvents: number; unreadNotifications: number; profileCompletion: number; trialStatus: string }; onNavigate: (section: Section) => void }) {
  const member = role === 'member'
  const cards: { key: Section; title: string; text: string; icon: typeof UserRound }[] = member
    ? [{ key: 'profile', title: 'Complete your profile', text: 'Add your work, skills and portfolio.', icon: UserRound }, { key: 'opportunities', title: 'Find opportunities', text: 'Explore projects from CCB clients.', icon: BriefcaseBusiness }, { key: 'events', title: 'Programs & events', text: 'See published CCB activities.', icon: CalendarDays }]
    : [{ key: 'profile', title: 'Complete your company profile', text: 'Share the organisation details clients need.', icon: Building2 }, { key: 'discovery', title: 'Discover professionals', text: 'Search public Member profiles.', icon: Search }, { key: 'opportunities', title: 'Post an opportunity', text: 'Create and manage project opportunities.', icon: BriefcaseBusiness }]
  return <>
    <div className="platform-stat-grid"><article><span>{member ? 'Applications' : 'Opportunities'}</span><strong>{stats.activityCount}</strong><small>Total records</small></article><article><span>Profile completion</span><strong>{stats.profileCompletion}%</strong><small>{member ? 'Member profile' : 'Organisation profile'}</small></article><article><span>Upcoming events</span><strong>{stats.upcomingEvents}</strong><small>Published events</small></article><article><span>Unread updates</span><strong>{stats.unreadNotifications}</strong><small>{stats.trialStatus}</small></article></div>
    <div className="platform-quick-grid">{cards.map(({ key, title, text, icon: Icon }) => <button key={key} onClick={() => onNavigate(key)}><span><Icon size={20}/></span><b>{title}</b><small>{text}</small><ArrowRight size={16}/></button>)}</div>
    <section className="platform-panel"><div className="platform-panel-head"><div><span className="eyebrow">RECENT ACTIVITY</span><h3>{member ? 'Your latest applications' : 'Your latest opportunities'}</h3></div><button className="workspace-link-button" onClick={() => onNavigate(member ? 'applications' : 'opportunities')}>View all <ArrowRight size={15}/></button></div>{rows.length ? rows.map((row) => <div className="workspace-list-row" key={String(row.id)}><div><b>{String(row.title ?? (row.work_opportunities as Row | undefined)?.title ?? 'Application')}</b><small>{String(row.status ?? 'submitted').replaceAll('_', ' ')}</small></div><time>{String(row.submitted_at ?? row.created_at ?? '').slice(0, 10)}</time></div>) : <Empty text="Your recent activity will appear here once you get started."/>}</section>
  </>
}

function ProfileForm({ isMember, profile, updateProfile, saveProfile, saving, categories, skills, roles, tools, selectedCategories, selectedSkills, selectedRoles, selectedTools, setSelectedCategories, setSelectedSkills, setSelectedRoles, setSelectedTools, portfolio, socials, addPortfolio, removePortfolio, addSocialAccount, uploadProfileImage, suggestTaxonomy }: {
  isMember: boolean; profile: Row; updateProfile: (key: string, value: unknown) => void; saveProfile: (event: FormEvent<HTMLFormElement>) => void; saving: boolean; categories: Row[]; skills: Row[]; roles: Row[]; tools: Row[]; selectedCategories: string[]; selectedSkills: string[]; selectedRoles: string[]; selectedTools: string[]; setSelectedCategories: (value: string[]) => void; setSelectedSkills: (value: string[]) => void; setSelectedRoles: (value: string[]) => void; setSelectedTools: (value: string[]) => void; portfolio: Row[]; socials: Row[]; addPortfolio: (event: FormEvent<HTMLFormElement>) => void; removePortfolio: (id: string) => void; addSocialAccount: (event: FormEvent<HTMLFormElement>) => void; uploadProfileImage: (file?: File) => void; suggestTaxonomy: (event: FormEvent<HTMLFormElement>) => void
}) {
  const imageId = val(profile, isMember ? 'profile_media_id' : 'logo_media_id')
  return <>
    <form className="workspace-form platform-panel" onSubmit={saveProfile}>
      <div className="platform-panel-head"><div><span className="eyebrow">PROFILE DETAILS</span><h3>{isMember ? 'Professional profile' : 'Organisation details'}</h3></div><button className="btn btn-primary" disabled={saving}>{saving ? 'Saving...' : 'Save profile'}</button></div>
      <div className="workspace-fields">
        <Field label="Full name" value={val(profile, 'display_name')} onChange={(v) => updateProfile('display_name', v)} required minLength={2} maxLength={160}/>
        {isMember ? <>
          <Field label="Professional headline" value={val(profile, 'headline')} onChange={(v) => updateProfile('headline', v)} required placeholder="e.g. Video editor and visual storyteller" />
          <Field label="Location" value={val(profile, 'location')} onChange={(v) => updateProfile('location', v)} placeholder="City, country" />
          <Field label="Years of experience" value={val(profile, 'years_experience')} onChange={(v) => updateProfile('years_experience', v)} type="number" min="0" />
          <Field label="Minimum expected rate (INR)" value={val(profile, 'expected_rate_min')} onChange={(v) => updateProfile('expected_rate_min', v)} type="number" min="0" />
          <Field label="Maximum expected rate (INR)" value={val(profile, 'expected_rate_max')} onChange={(v) => updateProfile('expected_rate_max', v)} type="number" min="0" />
          <SelectField label="Rate basis" value={val(profile, 'expected_rate_period')} onChange={(v) => updateProfile('expected_rate_period', v)} options={['', 'project', 'hourly', 'daily', 'monthly']} />
          <SelectField label="Availability" value={val(profile, 'availability') || 'available'} onChange={(v) => updateProfile('availability', v)} options={['available', 'limited', 'unavailable']} />
          <label className="workspace-field workspace-field-full">Preferred work arrangements<div className="workspace-chip-list">{['remote', 'hybrid', 'on_site'].map((item) => <label className="workspace-chip" key={item}><input type="checkbox" checked={Array.isArray(profile.work_preferences) && profile.work_preferences.includes(item)} onChange={(event) => { const current = Array.isArray(profile.work_preferences) ? profile.work_preferences as string[] : []; updateProfile('work_preferences', event.target.checked ? [...current, item] : current.filter((value) => value !== item)) }}/>{item.replaceAll('_', ' ')}</label>)}</div></label>
          <SelectField label="Contact preference" value={val(profile, 'contact_preference') || 'platform'} onChange={(v) => updateProfile('contact_preference', v)} options={['platform', 'email', 'none']} />
          <Field label="Portfolio website" value={val(profile, 'portfolio_website')} onChange={(v) => updateProfile('portfolio_website', v)} type="url" placeholder="https://" />
          <label className="workspace-field workspace-field-full">Bio<textarea value={val(profile, 'bio')} onChange={(event) => updateProfile('bio', event.target.value)} rows={5} maxLength={5000}/></label>
          <Field label="Professional interests (comma separated)" value={Array.isArray(profile.professional_interests) ? profile.professional_interests.join(', ') : val(profile, 'professional_interests')} onChange={(v) => updateProfile('professional_interests', v)} placeholder="Film, brand campaigns, photography" />
          <label className="workspace-check"><input type="checkbox" checked={Boolean(profile.is_public)} onChange={(event) => updateProfile('is_public', event.target.checked)}/><span>Show my professional profile in Client discovery</span></label>
          <label className="workspace-check"><input type="checkbox" checked={Boolean(profile.insights_sharing_enabled)} onChange={(event) => updateProfile('insights_sharing_enabled', event.target.checked)}/><span>Allow eligible Clients to view authorised social insights</span></label>
        </> : <>
          <Field label="Company or brand name" value={val(profile, 'company_name')} onChange={(v) => updateProfile('company_name', v)} required />
          <Field label="Organisation type" value={val(profile, 'organization_type')} onChange={(v) => updateProfile('organization_type', v)} placeholder="Brand, agency, business..." />
          <Field label="Industry" value={val(profile, 'industry')} onChange={(v) => updateProfile('industry', v)} />
          <Field label="Location" value={val(profile, 'location')} onChange={(v) => updateProfile('location', v)} />
          <Field label="Website" value={val(profile, 'website_url')} onChange={(v) => updateProfile('website_url', v)} type="url" placeholder="https://" />
          <Field label="Business email" value={val(profile, 'business_email')} onChange={(v) => updateProfile('business_email', v)} type="email" />
          <Field label="Business phone" value={val(profile, 'business_phone')} onChange={(v) => updateProfile('business_phone', v)} type="tel" />
          <label className="workspace-field workspace-field-full">Description<textarea value={val(profile, 'description')} onChange={(event) => updateProfile('description', event.target.value)} rows={5} maxLength={5000}/></label>
        </>}
        <div className="workspace-field workspace-field-full workspace-profile-image-field">{imageId ? <img className="workspace-profile-image-preview" src={`/api/media?id=${encodeURIComponent(imageId)}`} alt={isMember ? 'Your profile photo' : 'Your company logo'} /> : null}<label className="workspace-field">{isMember ? 'Profile photo' : 'Company logo'}<input type="file" accept="image/jpeg,image/png,image/webp,image/avif" disabled={saving} onChange={(event) => void uploadProfileImage(event.target.files?.[0])}/><small>Private R2 upload, up to 10 MB. {saving ? 'Uploading image...' : imageId ? 'Your image is attached to this profile.' : 'No image attached yet.'}</small></label></div>
        <div className="workspace-field workspace-field-full"><button className="btn btn-primary" disabled={saving}>{saving ? 'Saving...' : 'Save profile'} <ArrowRight size={15}/></button></div>
      </div>
    </form>
    <form className="platform-panel workspace-inline-form" onSubmit={suggestTaxonomy}><div className="platform-field-intro"><span className="eyebrow">TAXONOMY FEEDBACK</span><h3>Suggest a missing option</h3><p>Suggestions are reviewed by CCB Admin. Your suggestion will not be selectable until approved.</p></div><SelectField label="Suggestion type" name="suggestion_type" options={['role', 'skill', 'tool', 'category']}/><Field label="Name" name="name" required minLength={2} maxLength={160}/><label className="workspace-field workspace-field-full">Context<textarea name="description" rows={3} maxLength={2000}/></label><button className="btn btn-outline">Send for review</button></form>
    {isMember ? <>
      <TaxonomyPicker title="Professional categories" items={categories} selected={selectedCategories} setSelected={setSelectedCategories} />
      <TaxonomyPicker title="Skills" items={skills} selected={selectedSkills} setSelected={setSelectedSkills} />
      <TaxonomyPicker title="Professional roles and services" items={roles} selected={selectedRoles} setSelected={setSelectedRoles} />
      <TaxonomyPicker title="Tools and software" items={tools} selected={selectedTools} setSelected={setSelectedTools} />
      <section className="platform-panel"><div className="platform-panel-head"><div><span className="eyebrow">PORTFOLIO</span><h3>Selected work</h3></div></div><form className="workspace-inline-form" onSubmit={addPortfolio}><Field label="Project title" name="title" required/><Field label="Project URL" name="project_url" type="url" placeholder="https://"/><label className="workspace-field">Visibility<select name="visibility" defaultValue="public"><option value="public">Public to entitled Clients</option><option value="private">Private</option></select></label><label className="workspace-field workspace-field-full">Description<textarea name="description" rows={3}/></label><label className="workspace-field workspace-field-full">Portfolio images, video or PDF<input type="file" name="portfolio_files" accept="image/jpeg,image/png,image/webp,image/avif,image/gif,video/mp4,video/webm,video/quicktime,application/pdf" multiple/><small>Up to five files: images up to 10 MB, video up to 100 MB, PDF up to 20 MB each. Files stay private in R2.</small></label><button className="btn btn-primary" disabled={saving}>Add portfolio item <Plus size={15}/></button></form>{portfolio.map((item) => <div className="workspace-list-row" key={String(item.id)}><div><b>{String(item.title)}</b><small>{String(item.visibility)}{item.project_url ? `  |  ${String(item.project_url)}` : ''}</small>{asRows(item.portfolio_item_media).map((attachment) => { const media = attachment.media_assets as Row | undefined; return media ? <p key={String(media.id)}><a href={`/api/media?id=${String(media.id)}`} target="_blank" rel="noreferrer">{String(media.original_filename ?? "Portfolio attachment")}</a></p> : null })}</div><button className="workspace-icon-button" title="Remove portfolio item" aria-label={`Remove ${String(item.title)}`} onClick={() => void removePortfolio(String(item.id))}><Trash2 size={16}/></button></div>)}</section>
      <section className="platform-panel"><div className="platform-panel-head"><div><span className="eyebrow">SOCIAL PRESENCE</span><h3>Social profile links</h3></div></div><p className="workspace-muted">This saves profile links only. Instagram insights require an approved Meta connection and remain unavailable until the integration is configured.</p><form className="workspace-inline-form" onSubmit={addSocialAccount}><SelectField label="Platform" name="provider" options={['instagram', 'youtube', 'tiktok', 'linkedin', 'other']}/><Field label="Profile URL" name="profile_url" type="url" placeholder="https://" required/><button className="btn btn-outline">Add social link <Plus size={15}/></button></form>{socials.map((social) => <div className="workspace-list-row" key={String(social.id)}><div><b>{String(social.provider).toUpperCase()}</b><small>{String(social.profile_url)}  |  link only</small></div><span className="workspace-status">{social.sharing_enabled ? 'Shared' : 'Private'}</span></div>)}</section>
    </> : null}
  </>
}

function TaxonomyPicker({ title, items, selected, setSelected, name }: { title: string; items: Row[]; selected?: string[]; setSelected?: (value: string[]) => void; name?: string }) {
  const [filter, setFilter] = useState('')
  const [localSelected, setLocalSelected] = useState<string[]>([])
  const selectedIds = selected ?? localSelected
  const updateSelected = setSelected ?? setLocalSelected
  const selectedItems = selectedIds.map((id) => items.find((item) => String(item.id) === id) ?? { id, name: 'Previously selected option' })
  const normalizedFilter = filter.trim().toLowerCase()
  const visible = normalizedFilter
    ? items.filter((item) => !selectedIds.includes(String(item.id)) && String(item.name).toLowerCase().includes(normalizedFilter)).slice(0, 10)
    : []
  const add = (id: string) => { updateSelected([...selectedIds, id]); setFilter('') }
  const remove = (id: string) => updateSelected(selectedIds.filter((value) => value !== id))
  return <section className="platform-panel workspace-taxonomy-picker">
    <div className="platform-panel-head"><div><span className="eyebrow">APPROVED TAXONOMY</span><h3>{title}</h3></div></div>
    {selectedItems.length ? <div className="workspace-selected-taxonomy" aria-label={`Selected ${title.toLowerCase()}`}>{selectedItems.map((item) => <span className="workspace-selected-taxonomy-chip" key={String(item.id)}>{String(item.name)}<button type="button" onClick={() => remove(String(item.id))} aria-label={`Remove ${String(item.name)}`} title={`Remove ${String(item.name)}`}><X size={14}/></button></span>)}</div> : <p className="workspace-muted">No options selected yet.</p>}
    <div className="workspace-taxonomy-search"><label className="workspace-field">Search and add<input value={filter} onChange={(event) => setFilter(event.target.value)} onKeyDown={(event) => { if (event.key === 'Enter' && visible[0]) { event.preventDefault(); add(String(visible[0].id)) } }} placeholder={`Search ${title.toLowerCase()} to add...`} autoComplete="off"/></label>
      {visible.length ? <div className="workspace-taxonomy-options" role="listbox" aria-label={`${title} search results`}>{visible.map((item) => <button type="button" role="option" aria-selected="false" key={String(item.id)} onClick={() => add(String(item.id))}><Plus size={14}/>{String(item.name)}</button>)}</div> : null}
    </div>
    {name ? selectedIds.map((id) => <input key={id} type="hidden" name={name} value={id}/>) : null}
    {normalizedFilter && !visible.length ? <p className="workspace-muted">No matching approved options. Try another search.</p> : null}
  </section>
}

function MemberOpportunities({ rows, categories, skills, roles, tools, apply, page, total, setPage, filters, setFilters, search }: {
  rows: Row[]
  categories: Row[]
  skills: Row[]
  roles: Row[]
  tools: Row[]
  apply: (event: FormEvent<HTMLFormElement>, id: string) => void
  page: number
  total: number
  setPage: (page: number) => void
  filters: OpportunitySearchFilters
  setFilters: (filters: OpportunitySearchFilters) => void
  search: (filters: OpportunitySearchFilters) => void
}) {
  const update = (key: keyof OpportunitySearchFilters, value: string) => setFilters({ ...filters, [key]: value })
  return <>
    <form className="workspace-search" onSubmit={(event) => { event.preventDefault(); search(filters) }}>
      <Field label="Keyword" value={filters.query} onChange={(value) => update('query', value)} placeholder="Search titles, skills, roles or tools" />
      <Field label="Location" value={filters.location} onChange={(value) => update('location', value)} placeholder="City or region" />
      <SelectField label="Category" value={filters.category} onChange={(value) => update('category', value)} options={['', ...categories.map((item) => `${String(item.id)}|${String(item.name)}`)]} />
      <SelectField label="Role or service" value={filters.role} onChange={(value) => update('role', value)} options={['', ...roles.map((item) => `${String(item.id)}|${String(item.name)}`)]} />
      <SelectField label="Skill" value={filters.skill} onChange={(value) => update('skill', value)} options={['', ...skills.map((item) => `${String(item.id)}|${String(item.name)}`)]} />
      <SelectField label="Tool or software" value={filters.tool} onChange={(value) => update('tool', value)} options={['', ...tools.map((item) => `${String(item.id)}|${String(item.name)}`)]} />
      <SelectField label="Work arrangement" value={filters.arrangement} onChange={(value) => update('arrangement', value)} options={['', 'remote', 'on_site', 'hybrid']} />
      <Field label="Minimum experience (years)" type="number" min="0" value={filters.minimumExperience} onChange={(value) => update('minimumExperience', value)} />
      <Field label="Maximum budget (INR)" type="number" min="0" value={filters.maximumBudget} onChange={(value) => update('maximumBudget', value)} />
      <div className="workspace-search-actions"><button className="btn btn-primary" type="submit"><Search size={15} /> Search opportunities</button><button className="btn btn-outline" type="button" onClick={() => search(blankOpportunitySearch)}>Clear filters</button></div>
    </form>
    <div className="workspace-card-stack">{rows.map((row) => <article className="platform-panel opportunity-card" key={String(row.id)}><span className="workspace-status">Published</span><h3>{String(row.title)}</h3><p>{String(row.description)}</p><div className="workspace-chip-list">{asRows(row.opportunity_categories).map((item) => <span className="workspace-chip" key={String(item.category_id)}>{String((item.professional_categories as Row | undefined)?.name ?? '')}</span>)}{asRows(row.opportunity_skills).map((item) => <span className="workspace-chip" key={String(item.skill_id)}>{String((item.skills as Row | undefined)?.name ?? '')}</span>)}</div><div className="opportunity-meta">{row.location ? <span>{String(row.location)}</span> : null}{row.work_arrangement ? <span>{String(row.work_arrangement).replaceAll('_', ' ')}</span> : null}{row.experience_min_years ? <span>{String(row.experience_min_years)}+ years experience</span> : null}{row.deadline ? <span>Deadline {String(row.deadline)}</span> : null}{row.budget_min != null || row.budget_max != null ? <span>{String(row.currency_code || 'INR')} {String(row.budget_min ?? 'Not set')} to {String(row.budget_max ?? 'Not set')}</span> : null}</div><details className="workspace-details"><summary>Apply to this opportunity</summary><form className="workspace-inline-form" onSubmit={(event) => apply(event, String(row.id))}><label className="workspace-field workspace-field-full">Cover message<textarea name="cover_message" rows={4} maxLength={5000} placeholder="Tell the client why this project fits your experience." /></label><button className="btn btn-primary">Submit application <ArrowRight size={15} /></button></form></details></article>)}{rows.length === 0 ? <Empty text="No published opportunities match these filters." /> : null}</div>
    {total > 20 ? <div className="workspace-pagination"><button className="btn btn-outline" type="button" disabled={page === 0} onClick={() => setPage(page - 1)}>Previous</button><span>Page {page + 1} of {Math.ceil(total / 20)}</span><button className="btn btn-outline" type="button" disabled={(page + 1) * 20 >= total} onClick={() => setPage(page + 1)}>Next</button></div> : null}
  </>
}

function ClientOpportunities({ rows, categories, skills, roles, tools, create, edit, setStatus, saving }: { rows: Row[]; categories: Row[]; skills: Row[]; roles: Row[]; tools: Row[]; create: (event: FormEvent<HTMLFormElement>) => void; edit: (id: string, event: FormEvent<HTMLFormElement>) => void; setStatus: (id: string, status: string) => void; saving: boolean }) {
  return <>
    <details className="platform-panel workspace-details" open={rows.length === 0}><summary><b><Plus size={16}/> Create a work opportunity</b></summary><p className="workspace-muted">New opportunities start as private drafts. Choose target categories and skills so Members can filter relevant work.</p><form className="workspace-fields" onSubmit={create}><Field label="Opportunity title" name="title" required minLength={3}/><Field label="Location" name="location" placeholder="Remote or city"/><label className="workspace-field workspace-field-full">Description<textarea name="description" rows={5} minLength={20} maxLength={12000} required/></label><Field label="Budget minimum (INR)" name="budget_min" type="number" min="0"/><Field label="Budget maximum (INR)" name="budget_max" type="number" min="0"/><SelectField label="Budget basis" name="budget_type" options={['fixed', 'hourly', 'daily', 'monthly_salary']}/><label className="workspace-check"><input type="checkbox" name="budget_negotiable"/><span>Budget is negotiable</span></label><Field label="Payment terms" name="payment_terms" placeholder="e.g. 50% advance"/><SelectField label="Work type" name="work_type" options={['project', 'freelance', 'contract', 'part_time', 'full_time', 'ongoing']}/><Field label="Professionals required" name="professionals_required" type="number" min="1"/><Field label="Minimum experience (years)" name="experience_min_years" type="number" min="0"/><Field label="Maximum experience (years)" name="experience_max_years" type="number" min="0"/><SelectField label="Required availability" name="required_availability" options={['any', 'available', 'limited']}/><SelectField label="Required skills matching" name="skills_match_mode" options={['any', 'all']}/><SelectField label="Work arrangement" name="work_arrangement" options={['remote', 'on_site', 'hybrid']}/><Field label="Start date" name="start_date" type="date"/><Field label="Application deadline" name="application_deadline" type="datetime-local"/><Field label="Project deadline" name="deadline" type="date"/><label className="workspace-field workspace-field-full">Additional requirements<textarea name="additional_requirements" rows={3}/></label><TaxonomyPicker title="Target categories" items={categories} name="category_ids"/><TaxonomyPicker title="Required skills" items={skills} name="skill_ids"/><TaxonomyPicker title="Mandatory skills" items={skills} name="mandatory_skill_ids"/><TaxonomyPicker title="Target roles and services" items={roles} name="role_ids"/><TaxonomyPicker title="Required tools and software" items={tools} name="tool_ids"/><button className="btn btn-primary" disabled={saving}>{saving ? 'Saving...' : 'Save draft'} <ArrowRight size={15}/></button></form></details>
    <div className="workspace-card-stack">{rows.map((row) => <article className="platform-panel opportunity-card" key={String(row.id)}><span className="workspace-status">{String(row.status).replaceAll('_', ' ')}</span><h3>{String(row.title)}</h3><p>{String(row.description)}</p><details className="workspace-details"><summary>Edit opportunity details</summary><form className="workspace-fields" onSubmit={(event) => edit(String(row.id), event)}><Field label="Title" name="title" defaultValue={String(row.title ?? '')} required minLength={3}/><Field label="Location" name="location" defaultValue={String(row.location ?? '')}/><label className="workspace-field workspace-field-full">Description<textarea name="description" defaultValue={String(row.description ?? '')} rows={4} required minLength={20}/></label><Field label="Minimum budget (INR)" name="budget_min" type="number" min="0" defaultValue={row.budget_min == null ? '' : String(row.budget_min)}/><Field label="Maximum budget (INR)" name="budget_max" type="number" min="0" defaultValue={row.budget_max == null ? '' : String(row.budget_max)}/><SelectField label="Budget basis" name="budget_type" defaultValue={String(row.budget_type ?? 'fixed')} options={['fixed', 'hourly', 'daily', 'monthly_salary']}/><Field label="Payment terms" name="payment_terms" defaultValue={String(row.payment_terms ?? '')}/><SelectField label="Work type" name="work_type" defaultValue={String(row.work_type ?? 'project')} options={['project', 'freelance', 'contract', 'part_time', 'full_time', 'ongoing']}/><Field label="Minimum experience" name="experience_min_years" type="number" min="0" defaultValue={row.experience_min_years == null ? '' : String(row.experience_min_years)}/><Field label="Maximum experience" name="experience_max_years" type="number" min="0" defaultValue={row.experience_max_years == null ? '' : String(row.experience_max_years)}/><SelectField label="Work arrangement" name="work_arrangement" defaultValue={String(row.work_arrangement ?? 'remote')} options={['remote', 'hybrid', 'on_site']}/><SelectField label="Required availability" name="required_availability" defaultValue={String(row.required_availability ?? 'any')} options={['any', 'available', 'limited']}/><Field label="Application deadline" name="application_deadline" type="datetime-local" defaultValue={row.application_deadline ? new Date(String(row.application_deadline)).toISOString().slice(0,16) : ''}/><Field label="Project deadline" name="deadline" type="date" defaultValue={String(row.deadline ?? '')}/><label className="workspace-check"><input type="checkbox" name="budget_negotiable" defaultChecked={Boolean(row.budget_negotiable)}/><span>Budget is negotiable</span></label><button className="btn btn-primary">Save opportunity</button></form></details><div className="opportunity-meta">{row.location ? <span>{String(row.location)}</span> : null}{row.application_deadline ? <span>Closes {String(row.application_deadline).slice(0, 10)}</span> : null}</div><div className="workspace-action-row">{row.status === 'draft' ? <button className="btn btn-primary" onClick={() => setStatus(String(row.id), 'published')}>Publish</button> : null}{row.status === 'published' ? <><button className="btn btn-outline" onClick={() => setStatus(String(row.id), 'applications_closed')}>Close applications</button><button className="btn btn-outline" onClick={() => setStatus(String(row.id), 'in_progress')}>Mark in progress</button><button className="btn btn-outline" onClick={() => setStatus(String(row.id), 'cancelled')}>Cancel</button></> : null}{row.status === 'applications_closed' ? <><button className="btn btn-outline" onClick={() => setStatus(String(row.id), 'published')}>Reopen</button><button className="btn btn-outline" onClick={() => setStatus(String(row.id), 'in_progress')}>Mark in progress</button></> : null}{row.status === 'in_progress' ? <><button className="btn btn-primary" onClick={() => setStatus(String(row.id), 'completed')}>Mark complete</button><button className="btn btn-outline" onClick={() => setStatus(String(row.id), 'cancelled')}>Cancel</button></> : null}</div></article>)}{rows.length === 0 ? <Empty text="Your saved drafts and published opportunities will appear here."/> : null}</div>
  </>
}

function Applications({ isMember, rows, update, withdraw, review }: { isMember: boolean; rows: Row[]; update: (id: string, status: string, message: string) => void; withdraw: (id: string) => void; review: (event: FormEvent<HTMLFormElement>, opportunityId: string, reviewedUserId: string) => void }) {
  return <div className="workspace-card-stack">{rows.map((row) => { const opportunity = row.work_opportunities as Row | undefined; const memberProfile = row.member_profiles as Row | undefined; const userProfile = memberProfile?.user_profiles as Row | undefined; const canReview = opportunity?.status === 'completed' && row.status === 'selected'; const reviewee = isMember ? String(opportunity?.client_id ?? '') : String(row.member_id ?? ''); const transitions: Record<string, string[]> = { submitted: ['under_review', 'shortlisted', 'rejected'], under_review: ['shortlisted', 'selected', 'rejected'], shortlisted: ['under_review', 'selected', 'rejected'] }; return <article className="platform-panel" key={String(row.id)}><div className="platform-panel-head"><div><span className="eyebrow">{isMember ? 'SUBMITTED APPLICATION' : 'CANDIDATE APPLICATION'}</span><h3>{String(opportunity?.title ?? 'Opportunity')}</h3></div><span className="workspace-status">{String(row.status).replaceAll('_', ' ')}</span></div>{isMember ? <p>{String(row.client_message ?? 'The Client has not added an update yet.')}</p> : <p><b>{String(userProfile?.display_name ?? 'Member')}</b>{memberProfile?.headline ? `  |  ${String(memberProfile.headline)}` : ''}{memberProfile?.location ? `  |  ${String(memberProfile.location)}` : ''}</p>}{row.cover_message ? <blockquote className="workspace-quote">{String(row.cover_message)}</blockquote> : null}<small className="workspace-muted">Submitted {String(row.submitted_at ?? '').slice(0, 10)}</small>{asRows(row.application_status_history).map((change) => <small className="workspace-muted" key={String(change.id)}>{String(change.from_status).replaceAll('_', ' ')} → {String(change.to_status).replaceAll('_', ' ')} · {new Date(String(change.changed_at)).toLocaleString()}</small>)}{isMember && row.status === 'submitted' ? <div className="workspace-action-row"><button className="btn btn-outline" onClick={() => withdraw(String(row.id))}>Withdraw application</button></div> : null}{!isMember && transitions[String(row.status)] ? <div className="workspace-action-row">{transitions[String(row.status)].map((status) => <button className="btn btn-outline" key={status} onClick={() => update(String(row.id), status, '')}>{status.replaceAll('_', ' ')}</button>)}</div> : null}{canReview && reviewee ? <form className="workspace-inline-form review-form" onSubmit={(event) => review(event, String(row.opportunity_id), reviewee)}><SelectField label="Engagement rating" name="rating" options={['5', '4', '3', '2', '1']}/><label className="workspace-field workspace-field-full">Review<textarea name="review_text" rows={3} maxLength={2000} placeholder="Share feedback about the completed engagement."/></label><button className="btn btn-outline">Submit review</button><small className="workspace-muted">Reviews are held for Admin moderation before publication.</small></form> : null}</article> })}{rows.length === 0 ? <Empty text="No applications to show yet."/> : null}</div>
}

function Discovery({ rows, query, setQuery, location, setLocation, minimumExperience, setMinimumExperience, maximumExperience, setMaximumExperience, minimumRate, setMinimumRate, maximumRate, setMaximumRate, minimumRating, setMinimumRating, availability, setAvailability, categories, skills, roles, tools, category, setCategory, skill, setSkill, role, setRole, tool, setTool, search, savedIds, toggleSaved, contact, page, total, setPage }: { rows: Row[]; query: string; setQuery: (v: string) => void; location: string; setLocation: (v: string) => void; minimumExperience: string; setMinimumExperience: (v: string) => void; maximumExperience: string; setMaximumExperience: (v: string) => void; minimumRate: string; setMinimumRate: (v: string) => void; maximumRate: string; setMaximumRate: (v: string) => void; minimumRating: string; setMinimumRating: (v: string) => void; availability: string; setAvailability: (v: string) => void; categories: Row[]; skills: Row[]; roles: Row[]; tools: Row[]; category: string; setCategory: (v: string) => void; skill: string; setSkill: (v: string) => void; role: string; setRole: (v: string) => void; tool: string; setTool: (v: string) => void; search: () => void; savedIds: string[]; toggleSaved: (id: string) => void; contact: (event: FormEvent<HTMLFormElement>, memberId: string) => void; page: number; total: number; setPage: (page: number) => void }) {
  const pageCount = Math.max(1, Math.ceil(total / 20))
  return <>
    <form className="workspace-search" onSubmit={(event) => { event.preventDefault(); search() }}>
      <Field label="Name, headline or keyword" value={query} onChange={setQuery} placeholder="Search professionals"/>
      <Field label="Location" value={location} onChange={setLocation} placeholder="City or region"/>
      <SelectField label="Category" value={category} onChange={setCategory} options={['', ...categories.map((item) => `${String(item.id)}|${String(item.name)}`)]}/>
      <SelectField label="Role or service" value={role} onChange={setRole} options={['', ...roles.map((item) => `${String(item.id)}|${String(item.name)}`)]}/>
      <SelectField label="Skill" value={skill} onChange={setSkill} options={['', ...skills.map((item) => `${String(item.id)}|${String(item.name)}`)]}/>
      <SelectField label="Tool or software" value={tool} onChange={setTool} options={['', ...tools.map((item) => `${String(item.id)}|${String(item.name)}`)]}/>
      <Field label="Minimum experience (years)" type="number" min="0" value={minimumExperience} onChange={setMinimumExperience}/>
      <Field label="Maximum experience (years)" type="number" min="0" value={maximumExperience} onChange={setMaximumExperience}/>
      <Field label="Minimum expected rate (INR)" type="number" min="0" value={minimumRate} onChange={setMinimumRate}/>
      <Field label="Maximum expected rate (INR)" type="number" min="0" value={maximumRate} onChange={setMaximumRate}/>
      <SelectField label="Minimum published rating" value={minimumRating} onChange={setMinimumRating} options={['', '3', '3.5', '4', '4.5']}/>
      <SelectField label="Availability" value={availability} onChange={setAvailability} options={['', 'available', 'limited', 'unavailable']}/>
      <button className="btn btn-primary"><Search size={15}/> Search</button>
    </form>
    <p className="workspace-muted" aria-live="polite">{total === 0 ? 'No matching profiles' : `Showing ${page * 20 + 1}–${Math.min(page * 20 + rows.length, total)} of ${total} professionals`}</p>
    <div className="workspace-card-stack">{rows.map((row) => <MemberCard key={String(row.user_id)} member={row} saved={savedIds.includes(String(row.user_id))} onSave={() => void toggleSaved(String(row.user_id))} onContact={(event) => contact(event, String(row.user_id))}/>)}</div>
    {total > 0 ? <div className="workspace-pagination"><button className="btn btn-outline" type="button" disabled={page === 0} onClick={() => setPage(page - 1)}>Previous</button><span>Page {page + 1} of {pageCount}</span><button className="btn btn-outline" type="button" disabled={page + 1 >= pageCount} onClick={() => setPage(page + 1)}>Next</button></div> : <Empty text="No public profiles matched this search. Search results require the Client discovery entitlement."/>}
  </>
}

function SavedProfessionals({ rows, remove, contact }: { rows: Row[]; remove: (id: string) => void; contact: (event: FormEvent<HTMLFormElement>, memberId: string) => void }) {
  return <div className="workspace-card-stack">{rows.map((row) => { const member = row.member_profiles as Row | undefined; return <MemberCard key={String(row.member_id)} member={member ?? {}} saved onSave={() => void remove(String(row.member_id))} onContact={(event) => contact(event, String(row.member_id))}/> })}{rows.length === 0 ? <Empty text="Save a professional from discovery to see them here."/> : null}</div>
}

function MemberCard({ member, saved, onSave, onContact }: { member: Row; saved: boolean; onSave: () => void; onContact?: (event: FormEvent<HTMLFormElement>) => void }) {
  const userProfile = member.user_profiles as Row | undefined
  const memberCats = asRows(member.member_categories)
  const memberSkills = asRows(member.member_skills)
  const memberRoles = asRows(member.member_roles)
  const memberTools = asRows(member.member_tools)
  const works = asRows(member.portfolio_items)
  return <article className="platform-panel member-result"><div className="member-result-main">{member.profile_media_id ? <img src={`/api/media?id=${String(member.profile_media_id)}`} alt="Member profile"/> : <span className="member-avatar"><UserRound size={22}/></span>}<div><h3>{String(userProfile?.display_name ?? 'CCB Member')}</h3><p>{String(member.headline ?? 'Professional profile')}</p><small>{String(member.location ?? 'Location not shared')}{member.years_experience ? `  |  ${String(member.years_experience)} years` : ''}{member.availability ? `  |  ${String(member.availability)}` : ''}</small></div><button className="btn btn-outline" onClick={onSave}>{saved ? 'Remove saved' : 'Save profile'}</button></div>{member.bio ? <p>{String(member.bio)}</p> : null}{member.expected_rate_min || member.expected_rate_max ? <small className="workspace-muted">Expected rate: INR {member.expected_rate_min == null ? 'Not set' : String(member.expected_rate_min)}{member.expected_rate_max == null ? '' : ` to ${String(member.expected_rate_max)}`} {String(member.expected_rate_period ?? '')}{member.rate_negotiable ? ' | Negotiable' : ''}</small> : null}{member.average_rating ? <small className="workspace-muted">Rating {Number(member.average_rating).toFixed(1)} / 5 ({String(member.review_count ?? 0)} published reviews)</small> : null}<div className="workspace-chip-list">{memberCats.map((item) => <span className="workspace-chip" key={String(item.category_id)}>{String((item.professional_categories as Row | undefined)?.name ?? '')}</span>)}{memberRoles.map((item) => <span className="workspace-chip" key={String(item.role_id)}>{String((item.professional_roles as Row | undefined)?.name ?? '')}</span>)}{memberSkills.map((item) => <span className="workspace-chip" key={String(item.skill_id)}>{String((item.skills as Row | undefined)?.name ?? '')}</span>)}{memberTools.map((item) => <span className="workspace-chip" key={String(item.tool_id)}>{String((item.professional_tools as Row | undefined)?.name ?? '')}</span>)}</div>{works.length ? <div className="workspace-portfolio-preview"><b>Portfolio</b>{works.map((work) => <p key={String(work.id)}>{String(work.title)}{work.description ? `  |  ${String(work.description)}` : ''}{work.project_url ? <>  |  <a href={String(work.project_url)} target="_blank" rel="noreferrer">View project</a></> : null}{asRows(work.portfolio_item_media).map((attachment) => { const media = attachment.media_assets as Row | undefined; return media ? <> · <a key={String(media.id)} href={`/api/media?id=${String(media.id)}`} target="_blank" rel="noreferrer">{String(media.original_filename ?? "Portfolio file")}</a></> : null })}</p>)}</div> : null}{onContact ? <details className="workspace-details"><summary>Contact this Member</summary><form className="workspace-inline-form" onSubmit={onContact}><Field label="Subject" name="subject" required maxLength={250}/><label className="workspace-field workspace-field-full">Message<textarea name="message" rows={4} required maxLength={5000}/></label><button className="btn btn-primary">Send enquiry</button></form></details> : null}</article>
}

function Events({ rows, enroll }: { rows: Row[]; enroll: (id: string) => void }) {
  const events = rows.filter((row) => !('_programs' in row))
  const programSummary = rows.find((row) => '_programs' in row)
  const programs = asRows(programSummary?._programs)
  const enrollments = asRows(programSummary?._enrollments)
  return <><section className="platform-panel"><div className="platform-panel-head"><div><span className="eyebrow">PROGRAMS & INITIATIVES</span><h3>Published programs</h3></div></div><p className="workspace-muted">Full online training courses and learning materials are coming soon. You can enroll in published CCB programs here.</p><div className="workspace-card-stack">{programs.map((program) => { const enrollment = enrollments.find((item) => item.program_id === program.id); return <article className="workspace-list-row" key={String(program.id)}><div><b>{String(program.title)}</b><small>{String(program.summary ?? '')}</small></div>{enrollment ? <span className="workspace-status">{String(enrollment.status)}</span> : <button className="workspace-link-button" onClick={() => enroll(String(program.id))}>Enroll</button>}</article> })}{programs.length === 0 ? <Empty text="No programs are published yet."/> : null}</div></section><section className="workspace-card-stack">{events.map((event) => { const closed = Boolean(event.rsvp_closed) || Boolean(event.registration_closes_at && new Date(String(event.registration_closes_at)).getTime() <= Date.now()); return <article className="platform-panel opportunity-card" key={String(event.id)}>{event.featured_media_id ? <img className="public-record-image" src={`/api/media?id=${encodeURIComponent(String(event.featured_media_id))}`} alt={String(event.title)} loading="lazy"/> : null}<span className="workspace-status">{closed ? 'Registration closed' : 'Published event'}</span><h3>{String(event.title)}</h3><p>{String(event.summary ?? event.description ?? '')}</p><div className="opportunity-meta">{event.starts_at ? <span>{new Date(String(event.starts_at)).toLocaleString()}</span> : null}{event.venue_name ? <span>{String(event.venue_name)}</span> : null}{event.is_online ? <span>Online</span> : null}{event.event_category ? <span>{String(event.event_category)}</span> : null}</div>{!closed && typeof event.external_rsvp_url === 'string' && event.external_rsvp_url.startsWith('https://') ? <a className="btn btn-primary" href={event.external_rsvp_url} target="_blank" rel="noopener noreferrer">Register Now <ArrowRight size={15}/></a> : <small className="workspace-muted">{closed ? 'Registration has closed.' : 'Registration details will be announced by CCB.'}</small>}</article> })}{events.length === 0 ? <Empty text="No published events are available yet."/> : null}</section></>
}
function ServiceRequests({ rows, submit }: { rows: Row[]; submit: (event: FormEvent<HTMLFormElement>) => void }) {
  return <><form className="platform-panel workspace-fields" onSubmit={submit}><div className="platform-field-intro"><span className="eyebrow">CONTACT CCB</span><h3>Submit a service request</h3><p>This is separate from a work opportunity you publish for Members.</p></div><SelectField label="Request type" name="request_type" options={['institutional_collaboration', 'campaign_support', 'brand_partnership', 'program_enquiry', 'other']}/><Field label="Subject" name="subject" required maxLength={250}/><label className="workspace-field workspace-field-full">Description<textarea name="description" rows={5} required maxLength={8000}/></label><button className="btn btn-primary">Submit request <ArrowRight size={15}/></button></form><section className="platform-panel"><div className="platform-panel-head"><div><span className="eyebrow">HISTORY</span><h3>Your service requests</h3></div></div>{rows.map((row) => <div className="workspace-list-row" key={String(row.id)}><div><b>{String(row.subject)}</b><small>{String(row.request_type).replaceAll('_', ' ')}  |  {String(row.status).replaceAll('_', ' ')}</small></div><time>{String(row.submitted_at).slice(0, 10)}</time></div>)}{rows.length === 0 ? <Empty text="Submitted requests will appear here."/> : null}</section></>
}

function Notifications({ rows, markRead }: { rows: Row[]; markRead: (id: string) => void }) {
  return <section className="platform-panel">{rows.map((row) => <article className={`workspace-notification ${row.read_at ? 'read' : 'unread'}`} key={String(row.id)}><div><b>{String(row.title)}</b><p>{String(row.message)}</p><small>{new Date(String(row.created_at)).toLocaleString()}</small></div>{row.read_at ? <span className="workspace-status">Read</span> : <button className="workspace-link-button" onClick={() => void markRead(String(row.id))}>Mark read</button>}</article>)}{rows.length === 0 ? <Empty text="Important platform updates will show here."/> : null}</section>
}

function Subscriptions({ rows }: { rows: Row[] }) {
  return <><div className="workspace-card-stack">{rows.map((row) => { const plan = row.subscription_plans as Row | undefined; const entitlements = asRows(row.subscription_entitlements); return <article className="platform-panel" key={String(row.id)}><div className="platform-panel-head"><div><span className="eyebrow">ACCOUNT ACCESS</span><h3>{String(plan?.name ?? 'Seven-day CCB trial')}</h3></div><span className="workspace-status">{String(row.status).replaceAll('_', ' ')}</span></div><p>{row.trial_ends_at ? `Trial ends ${new Date(String(row.trial_ends_at)).toLocaleString()}.` : row.current_period_ends_at ? `Current period ends ${new Date(String(row.current_period_ends_at)).toLocaleDateString()}.` : 'Basic profile access stays available.'}</p><div className="workspace-chip-list">{entitlements.map((item) => <span className="workspace-chip" key={String(item.feature_key)}>{String(item.feature_key).replaceAll('_', ' ')}: {item.enabled ? 'enabled' : 'disabled'}</span>)}</div><p className="workspace-muted">Plans and prices are managed by CCB Admin. Online payments are not active until a gateway and policies are configured.</p></article> })}{rows.length === 0 ? <Empty text="No subscription record was found. Your account still has basic profile access; ask Admin to review trial setup."/> : null}</div></>
}

function Empty({ text }: { text: string }) { return <div className="workspace-empty">{text}</div> }

function Field({ label, value, onChange, name, type = 'text', placeholder, required, defaultValue, min, minLength, maxLength }: { label: string; value?: string; onChange?: (value: string) => void; name?: string; type?: string; placeholder?: string; required?: boolean; defaultValue?: string; min?: string; minLength?: number; maxLength?: number }) {
  return <label className="workspace-field">{label}<input name={name} type={type} value={value} defaultValue={value === undefined ? defaultValue : undefined} onChange={onChange ? (event) => onChange(event.target.value) : undefined} placeholder={placeholder} required={required} min={min} minLength={minLength} maxLength={maxLength}/></label>
}

function SelectField({ label, value, defaultValue, onChange, name, options }: { label: string; value?: string; defaultValue?: string; onChange?: (value: string) => void; name?: string; options: string[] }) {
  return <label className="workspace-field">{label}<select name={name} value={value} defaultValue={value === undefined ? defaultValue ?? options[0] : undefined} onChange={onChange ? (event) => onChange(event.target.value) : undefined}>{options.map((option) => { const separator = option.indexOf('|'); const optionValue = separator >= 0 ? option.slice(0, separator) : option; const optionLabel = separator >= 0 ? option.slice(separator + 1) : option; return <option key={option} value={optionValue}>{optionLabel ? optionLabel.replaceAll('_', ' ').replace(/^\w/, (char) => char.toUpperCase()) : 'Any'}</option> })}</select></label>
}


function MemberEnquiries({ rows }: { rows: Row[] }) {
  return <section className="platform-panel"><div className="platform-panel-head"><div><span className="eyebrow">INBOX</span><h3>Client enquiries</h3></div></div>{rows.map((row) => <article className="workspace-notification" key={String(row.id)}><div><b>{String(row.subject)}</b><p>{String(row.message)}</p><small>{new Date(String(row.created_at)).toLocaleString()} · {String(row.status).replaceAll('_', ' ')}</small></div></article>)}{rows.length === 0 ? <Empty text="Client enquiries will appear here."/> : null}</section>
}

function MemberMembershipApplications({ rows }: { rows: Row[] }) {
  return <section className="platform-panel"><div className="platform-panel-head"><div><span className="eyebrow">SUBMISSION HISTORY</span><h3>Membership applications</h3></div></div>{rows.map((row) => <article className="workspace-notification" key={String(row.id)}><div><b>{String(row.requested_category ?? 'Membership application')}</b><p>{String(row.message ?? '')}</p><small>Submitted {new Date(String(row.submitted_at)).toLocaleString()}</small></div><span className="workspace-status">{String(row.status).replaceAll('_', ' ')}</span></article>)}{rows.length === 0 ? <Empty text="No membership application is linked to this account yet. Applications sent while signed in appear here."/> : null}</section>
}

function SearchHistory({ rows }: { rows: Row[] }) {
  return <section className="platform-panel"><div className="platform-panel-head"><div><span className="eyebrow">DISCOVERY ACTIVITY</span><h3>Recent searches</h3></div></div>{rows.map((row) => { const filters = row.search_filters as Row | undefined; return <article className="workspace-list-row" key={String(row.id)}><div><b>{String(filters?.query || 'All professionals')}</b><small>{[filters?.location, filters?.category_id ? 'Category filter' : null, filters?.skill_id ? 'Skill filter' : null].filter(Boolean).join(' · ') || 'No additional filters'}</small></div><time>{new Date(String(row.searched_at)).toLocaleString()}</time></article> })}{rows.length === 0 ? <Empty text="Your Member discovery searches will appear here."/> : null}</section>
}



