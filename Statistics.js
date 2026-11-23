import React, {useEffect, useState} from 'react';
import {Pressable, ScrollView, Text, View} from 'react-native';
import {fishingSummary} from './stats';

/**
 * Show counts based on recorded data without assuming unlogged trip history.
 */
export default function Statistics({base, catches, api, styles, onBack}) {
  const [trips, setTrips] = useState(null);
  const [message, setMessage] = useState('Loading trips…');
  useEffect(() => {
    let active = true;
    api(base, '/api/trips').then(rows => {
      if (!Array.isArray(rows)) throw Error('Unexpected response.');
      if (active) { setTrips(rows); setMessage(''); }
    }).catch(() => {
      if (active) { setTrips(null); setMessage('Trip counts need a connection and a server that supports trips.'); }
    });
    return () => { active = false; };
  }, [api, base]);
  const year = new Date().getFullYear(), summary = fishingSummary(catches, trips, year);
  const row = (label, value) => <View key={label} style={{flexDirection:'row',justifyContent:'space-between',paddingVertical:12,borderBottomWidth:1,borderColor:'#dce5dc'}}><Text style={[styles.paragraph,{flex:1,marginRight:12}]}>{label}</Text><Text style={styles.cardTitle}>{value}</Text></View>;
  const section = (title, items, empty) => <View style={{marginTop:28}}><Text style={styles.cardTitle}>{title}</Text>{items.length ? items.map(item => row(item.label, item.count)) : <Text style={styles.paragraph}>{empty}</Text>}</View>;
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'].map((label, index) => ({label, count:summary.months[index]})).filter(item => item.count);
  return <ScrollView contentContainerStyle={styles.content}><Pressable accessibilityRole="button" onPress={onBack}><Text style={styles.textLink}>‹ Back to your journal</Text></Pressable><Text style={styles.eyebrow}>YOUR FISHING</Text><Text style={styles.title}>Statistics</Text><Text style={styles.subtitle}>A closer look at what you have recorded.</Text>
    {row('Catches',summary.catches)}{row('Different species names',summary.species)}{row(`Catches dated ${year}`,summary.caughtThisYear)}{row('Trips recorded',summary.trips == null ? '—' : summary.trips)}{row('Trips with linked catches',summary.tripsWithLinkedCatches == null ? '—' : summary.tripsWithLinkedCatches)}
    {!!message && <Text style={styles.paragraph}>{message}</Text>}
    {section('Catches by year',summary.years,'No dated catches yet.')}
    {section('Catches by month · all years',months,'No dated catches yet.')}
    {section('Most recorded fish',summary.topSpecies.slice(0, 5),'Add a species to a catch to see it here.')}
    {section('Most recorded places',summary.topPlaces.slice(0, 5),'Add a place to a catch to see it here.')}
    <Text style={[styles.small,{marginTop:24}]}>These counts use saved species and place names, so different spellings are counted separately. {summary.undatedCatches ? `${summary.undatedCatches} catches have no valid date and are excluded from the date breakdowns. ` : ''}Older catches are not automatically assigned to trips. A trip with no linked catches is not necessarily an unsuccessful trip. Offline drafts are not included until synced.</Text>
  </ScrollView>;
}
