import React, {useCallback, useEffect, useState} from 'react';
import {Alert, Image, KeyboardAvoidingView, Modal, Platform, Pressable, SafeAreaView, ScrollView, Text, TextInput, View} from 'react-native';
import * as Crypto from 'expo-crypto';
import * as Location from 'expo-location';
import * as ImagePicker from 'expo-image-picker';
import {File} from 'expo-file-system';
import {ImageManipulator, SaveFormat} from 'expo-image-manipulator';
import {appendPhoto} from './photo-upload';
import MapView, {Marker} from 'react-native-maps';

/**
 * Present connected fishing trips and preserve the form when a request fails.
 */
export default function Trips({base, catches, api, toUK, ukToISO, todayUK, styles, onOpenCatch, onEditingChange, onBusyChange, onOpenStats, onOpenRecords}) {
  const [trips, setTrips] = useState([]);
  const [status, setStatus] = useState('Loading trips…');
  const [form, setForm] = useState(null);
  const [selected, setSelected] = useState(null);
  const [busy, setBusy] = useState(false);
  const [viewPhoto, setViewPhoto] = useState(null);
  const [pendingPhotos, setPendingPhotos] = useState({});

  const load = useCallback(async () => {
    try {
      const rows = await api(base, '/api/trips');
      if (!Array.isArray(rows)) throw Error('Unexpected response.');
      setTrips(rows);
      setSelected(previous => previous ? rows.find(trip=>trip.id===previous.id) || null : null);
      setStatus('');
    } catch {
      setStatus('Could not load trips. Check your connection and make sure the Fish On server supports trips.');
    }
  }, [api, base]);
  useEffect(() => { load(); }, [load]);
  const editing = Boolean(form);
  useEffect(() => { onEditingChange(editing); return () => onEditingChange(false); }, [editing, onEditingChange]);
  useEffect(() => { onBusyChange(busy); return () => onBusyChange(false); }, [busy, onBusyChange]);

  /**
   * Start a new trip or edit an existing one without changing any catch.
   */
  function editTrip(trip) {
    setSelected(null);
    setForm(trip ? {...trip, date:toUK(trip.date), end_date:toUK(trip.end_date), latitude:trip.latitude == null ? '' : String(trip.latitude), longitude:trip.longitude == null ? '' : String(trip.longitude), catch_ids:[...trip.catch_ids]} : {
      id:Crypto.randomUUID().replace(/-/g,''), date:todayUK(), end_date:'', place:'', start_time:'', end_time:'', timezone:'',
      latitude:'', longitude:'', method:'', bait:'', target_species:'', weather:'', notes:'', catch_ids:[],
    });
  }

  /**
   * Update a single unsaved trip field.
   */
  function update(key, value) {
    setForm(previous => previous ? ({...previous, [key]:value}) : previous);
  }

  /**
   * Add the current location when the user explicitly requests it.
   */
  async function useCurrentLocation() {
    try {
      const permission = await Location.requestForegroundPermissionsAsync();
      if (!permission.granted) { Alert.alert('Location access needed', 'Allow location access to use your current position.'); return; }
      const position = await Location.getCurrentPositionAsync({accuracy:Location.Accuracy.Balanced});
      setForm(previous => previous ? {...previous, latitude:String(position.coords.latitude.toFixed(6)), longitude:String(position.coords.longitude.toFixed(6))} : previous);
    } catch { Alert.alert('Location unavailable', 'Tap the map or enter coordinates manually.'); }
  }

  /**
   * Persist the trip using a stable ID and keep the draft on failure.
   */
  async function save() {
    if (busy || !form) return;
    const date = ukToISO(form.date || '');
    if (!date) { Alert.alert('Date needed', 'Enter a valid date as DD/MM/YYYY.'); return; }
    const endDate = ukToISO(form.end_date || '');
    if (endDate === null) { Alert.alert('Invalid end date', 'Enter an end date as DD/MM/YYYY, or leave it blank.'); return; }
    const lat = String(form.latitude || '').trim(), lon = String(form.longitude || '').trim();
    if (Boolean(lat) !== Boolean(lon) || (lat && (!Number.isFinite(Number(lat)) || !Number.isFinite(Number(lon)) || Math.abs(Number(lat)) > 90 || Math.abs(Number(lon)) > 180))) {
      Alert.alert('Invalid coordinates', 'Enter valid latitude and longitude, or leave both blank.'); return;
    }
    setBusy(true);
    try {
      const payload={...form, date, end_date:endDate, latitude:lat ? Number(lat) : null, longitude:lon ? Number(lon) : null};
      delete payload.photos;
      await api(base, '/api/trips', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(payload)});
      setForm(null);
      await load();
    } catch (error) {
      Alert.alert('Trip not saved', `${error.message || 'Check the connection and try again.'} Your details are still here.`);
    } finally { setBusy(false); }
  }

  /**
   * Upload one chosen trip photograph after converting it to JPEG.
   */
  async function addPhoto() {
    if (!selected || busy) return;
    setBusy(true);
    try {
      let prepared = pendingPhotos[selected.id];
      if (!prepared) {
        const permission = await ImagePicker.requestMediaLibraryPermissionsAsync();
        if (!permission.granted) { Alert.alert('Photo access needed', 'Allow photo access to choose a trip picture.'); return; }
        const picked = await ImagePicker.launchImageLibraryAsync({mediaTypes:['images'],quality:1});
        if (picked.canceled || !picked.assets?.[0]) return;
        const context = ImageManipulator.manipulate(picked.assets[0].uri);
        const image = await context.renderAsync();
        const jpeg = await image.saveAsync({format:SaveFormat.JPEG,compress:0.9});
        prepared = {id:Crypto.randomUUID().replace(/-/g,''),asset:jpeg};
        setPendingPhotos(previous=>({...previous,[selected.id]:prepared}));
      }
      const formData = new FormData();
      formData.append('photo_id',prepared.id);
      appendPhoto(formData,prepared.asset,File);
      await api(base,'/api/trips/'+selected.id+'/photos',{method:'POST',body:formData});
      setPendingPhotos(previous=>{const next={...previous};delete next[selected.id];return next});
      await load();
    } catch (error) { Alert.alert('Photo not saved', (error.message || 'Check the connection and try again.')+' You can retry while this screen is open.'); }
    finally { setBusy(false); }
  }

  /**
   * Remove a trip photo only after explicit confirmation.
   */
  function removePhoto(photo) {
    if (!selected || busy) return;
    Alert.alert('Remove trip photo?', 'This removes this photo from the trip.', [
      {text:'Cancel',style:'cancel'},
      {text:'Remove',style:'destructive',onPress:async()=>{
        setBusy(true);
        try { const result=await api(base,'/api/trips/'+selected.id+'/photos/'+photo.id,{method:'DELETE'}); await load(); if(result.warning)Alert.alert('Photo removed',result.warning); }
        catch (error) { Alert.alert('Could not remove photo',error.message || 'Check the connection and try again.'); }
        finally { setBusy(false); }
      }},
    ]);
  }

  /**
   * Remove a trip after confirmation while retaining all linked catches.
   */
  function remove(trip) {
    Alert.alert('Delete trip?', 'The trip and its own photos will be deleted, but its catches and their photos will remain in your journal.', [
      {text:'Cancel', style:'cancel'},
      {text:'Delete trip', style:'destructive', onPress:async () => {
        try { const result=await api(base, '/api/trips/'+trip.id, {method:'DELETE'}); setSelected(null); await load(); if(result.warning)Alert.alert('Trip deleted',result.warning); }
        catch (error) { Alert.alert('Could not delete trip', error.message || 'Check the connection and try again.'); }
      }},
    ]);
  }

  const action = (title, onPress, secondary=false) => <Pressable accessibilityRole="button" disabled={busy} accessibilityState={{disabled:busy}} onPress={onPress} style={[styles.button, secondary && styles.buttonSecondary, busy && {opacity:0.6}]}><Text style={[styles.buttonText, secondary && styles.buttonTextSecondary]}>{title}</Text></Pressable>;
  const field = (key, label, placeholder, multiline=false, keyboardType='default') => <View key={key} style={styles.field}><Text style={styles.label}>{label}</Text><TextInput style={[styles.input, multiline && styles.multiline]} value={String(form?.[key] ?? '')} onChangeText={value=>update(key,value)} placeholder={placeholder} placeholderTextColor="#81978a" multiline={multiline} keyboardType={keyboardType}/></View>;
  const linkedElsewhere = new Set(trips.filter(trip => trip.id !== form?.id).flatMap(trip => trip.catch_ids || []));
  const linked = trip => catches.filter(catchItem => (trip.catch_ids || []).includes(catchItem.id));
  const validPoint = Boolean(form && String(form.latitude).trim() && String(form.longitude).trim() && Number.isFinite(Number(form.latitude)) && Number.isFinite(Number(form.longitude)) && Math.abs(Number(form.latitude)) <= 90 && Math.abs(Number(form.longitude)) <= 180);

  if (form) return <KeyboardAvoidingView style={{flex:1}} behavior={Platform.OS==='ios'?'padding':undefined}><ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
    <Text style={styles.eyebrow}>FISHING TRIPS</Text><Text style={styles.title}>{trips.some(trip=>trip.id===form.id) ? 'Edit trip' : 'Log a trip'}</Text>
    <Text style={styles.paragraph}>Record your time on the water, whether or not you caught a fish. A connection is needed to save a trip.</Text>
    {field('date','Date (DD/MM/YYYY)','17/05/2026')}{field('place','Place','River, lake or fishery')}
    {field('start_time','Start time (24-hour)','06:30')}{field('end_date','End date (DD/MM/YYYY)','Optional, for an overnight trip')}{field('end_time','End time (24-hour)','12:00')}
    {field('method','Fishing method','Float, fly, lure…')}{field('bait','Bait / lures','What did you use?')}
    {field('target_species','Target species','Optional')}{field('weather','Weather','Optional, entered by you')}
    <Text style={[styles.cardTitle,{marginTop:20}]}>Trip location</Text><Text style={styles.small}>Tap the map or enter coordinates below.</Text>
    {action('Use my current location',useCurrentLocation,true)}
    <MapView style={{height:220,marginTop:10,borderRadius:6}} initialRegion={validPoint?{latitude:Number(form.latitude),longitude:Number(form.longitude),latitudeDelta:0.1,longitudeDelta:0.1}:{latitude:53,longitude:-2,latitudeDelta:9,longitudeDelta:8}} onPress={event=>{const point=event.nativeEvent.coordinate;setForm(previous=>previous?{...previous,latitude:String(point.latitude.toFixed(6)),longitude:String(point.longitude.toFixed(6))}:previous)}}>{validPoint&&<Marker coordinate={{latitude:Number(form.latitude),longitude:Number(form.longitude)}}/>}</MapView>
    {field('latitude','Latitude','Optional',false,'decimal-pad')}{field('longitude','Longitude','Optional',false,'decimal-pad')}
    {field('notes','Notes','Remember the day',true)}
    <Text style={[styles.cardTitle,{marginTop:20}]}>Catches on this trip</Text><Text style={styles.small}>Choose from your saved catches. A catch can belong to one trip.</Text>
    {catches.length===0&&<Text style={styles.muted}>No saved catches to link yet.</Text>}
    {catches.map(catchItem=>{const checked=form.catch_ids.includes(catchItem.id), unavailable=linkedElsewhere.has(catchItem.id);return <Pressable key={catchItem.id} disabled={unavailable} accessibilityRole="checkbox" accessibilityState={{checked,disabled:unavailable}} onPress={()=>update('catch_ids',checked?form.catch_ids.filter(id=>id!==catchItem.id):[...form.catch_ids,catchItem.id])} style={{paddingVertical:12,borderBottomWidth:1,borderColor:'#dce5dc',opacity:unavailable ? 0.55 : 1}}><Text style={styles.cardTitle}>{checked?'☑':'☐'} {catchItem.species}</Text><Text style={styles.small}>{toUK(catchItem.date)||'Date not recorded'}{unavailable?' · Already on another trip':''}</Text></Pressable>})}
    <Text style={styles.small}>Trip photos can be added after saving. Offline trip sync is not available yet.</Text>
    {action(busy?'Saving…':'Save trip',save)}{action('Cancel',()=>Alert.alert('Discard trip changes?', 'Your unsaved trip details will be lost.', [{text:'Keep editing',style:'cancel'},{text:'Discard',style:'destructive',onPress:()=>setForm(null)}]),true)}
  </ScrollView></KeyboardAvoidingView>;

  if (selected) return <ScrollView contentContainerStyle={styles.content}>
    {action('Back to trips',()=>setSelected(null),true)}<Text style={styles.eyebrow}>YOUR TRIP</Text><Text style={styles.title}>{selected.place || 'Fishing trip'}</Text><Text style={styles.subtitle}>{toUK(selected.date) || 'Date not recorded'}</Text>
    {[['End date',toUK(selected.end_date)],['Time',[selected.start_time,selected.end_time].filter(Boolean).join(' – ')],['Method',selected.method],['Bait / lures',selected.bait],['Target species',selected.target_species],['Weather',selected.weather],['Coordinates',selected.latitude != null && selected.longitude != null ? `${selected.latitude}, ${selected.longitude}` : ''],['Notes',selected.notes]].map(([label,value])=>value?<Text key={label} style={styles.paragraph}><Text style={styles.bold}>{label}: </Text>{value}</Text>:null)}
    <Text style={[styles.cardTitle,{marginTop:20}]}>Linked catches</Text>{linked(selected).length ? linked(selected).map(catchItem=><Pressable key={catchItem.id} accessibilityRole="button" onPress={()=>onOpenCatch(catchItem)} style={styles.fishRow}><View style={styles.rowText}><Text style={styles.cardTitle}>{catchItem.species}</Text><Text style={styles.small}>{toUK(catchItem.date)||'Date not recorded'}</Text></View><Text style={styles.chevron}>›</Text></Pressable>) : <Text style={styles.muted}>No catches linked to this trip.</Text>}
    <Text style={[styles.cardTitle,{marginTop:22}]}>Trip photos</Text><Text style={styles.small}>Separate from photos attached to your catches.</Text>
    {(selected.photos||[]).length===0&&<Text style={styles.muted}>No trip photos yet.</Text>}
    {(selected.photos||[]).map(photo=><View key={photo.id}><Pressable accessibilityRole="button" accessibilityLabel="View trip photo" onPress={()=>setViewPhoto(photo)}><Image source={{uri:base+photo.url}} style={styles.detailImage} resizeMode="contain"/><Text style={styles.small}>Tap to view the full photo</Text></Pressable>{action('Remove photo',()=>removePhoto(photo),true)}</View>)}
    {action(busy?'Please wait…':pendingPhotos[selected.id]?'Retry photo upload':'Add a trip photo',addPhoto,true)}
    {!!pendingPhotos[selected.id]&&action('Discard pending photo',()=>setPendingPhotos(previous=>{const next={...previous};delete next[selected.id];return next}),true)}
    <Modal visible={!!viewPhoto} animationType="slide" onRequestClose={()=>setViewPhoto(null)}><SafeAreaView style={styles.safe}><View style={styles.modalHeader}><Text style={styles.modalTitle}>Trip photo</Text><Pressable accessibilityRole="button" accessibilityLabel="Close photo" onPress={()=>setViewPhoto(null)}><Text style={styles.close}>×</Text></Pressable></View>{viewPhoto&&<Image source={{uri:base+viewPhoto.url}} style={{width:'100%',flex:1,backgroundColor:'#101714'}} resizeMode="contain"/>}</SafeAreaView></Modal>
    {action('Edit trip',()=>editTrip(selected))}{action('Delete trip',()=>remove(selected),true)}
  </ScrollView>;

  return <ScrollView contentContainerStyle={styles.content}><Text style={styles.eyebrow}>YOUR FISHING</Text><Text style={styles.title}>Fishing trips</Text><Text style={styles.subtitle}>Keep the day, whether or not you caught a fish.</Text>
    {status ? <><Text style={styles.paragraph}>{status}</Text>{action('Try again',load,true)}{action('View statistics',onOpenStats,true)}{action('Personal records',onOpenRecords,true)}</> : <>{action('+ Log a trip',()=>editTrip(null))}{action('View statistics',onOpenStats,true)}{action('Personal records',onOpenRecords,true)}<View style={styles.pendingBox}><Text style={styles.pendingTitle}>{trips.length} {trips.length===1?'trip':'trips'} recorded</Text><Text style={styles.small}>{trips.filter(trip=>(trip.catch_ids||[]).length>0).length} with linked catches. Older standalone catches are not counted as trips.</Text></View>{trips.length===0&&<Text style={styles.muted}>No trips recorded yet.</Text>}{trips.map(trip=><Pressable key={trip.id} accessibilityRole="button" onPress={()=>setSelected(trip)} style={styles.fishRow}><View style={styles.rowText}><Text style={styles.cardTitle}>{trip.place||'Fishing trip'}</Text><Text style={styles.small}>{toUK(trip.date)} · {(trip.catch_ids||[]).length} linked {(trip.catch_ids||[]).length===1?'catch':'catches'}</Text></View><Text style={styles.chevron}>›</Text></Pressable>)}</>}
  </ScrollView>;
}
